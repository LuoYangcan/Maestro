import ComposableArchitecture
import Foundation

@MainActor
final class PullRequestRefreshCoordinator {
  nonisolated struct Request: Equatable, Sendable {
    let repositoryID: Repository.ID
    let repositoryRootURL: URL
    let host: String
    let owner: String
    let repo: String
    let branches: [String]
    let worktreeIDs: [Worktree.ID]
  }

  nonisolated enum Outcome: Sendable, Equatable {
    case refreshed(
      repositoryID: Repository.ID,
      repositoryRootURL: URL,
      worktreeIDs: [Worktree.ID],
      prsByBranch: [String: GithubPullRequest]
    )
    case failed(
      repositoryID: Repository.ID,
      worktreeIDs: [Worktree.ID],
      message: String
    )
  }

  private let githubCLI: GithubCLIClient
  private let clock: any Clock<Duration>
  private let debounceWindow: Duration
  private let softTimeout: Duration
  private let aliasLimit: Int
  private let resultHandler: @MainActor (Outcome) -> Void

  private var pendingByHost: [String: [Repository.ID: Request]] = [:]
  private var flushTaskByHost: [String: Task<Void, Never>] = [:]
  private var inflightHosts: Set<String> = []
  private var queuedByHost: [String: [Repository.ID: Request]] = [:]

  private let logger = SupaLogger("BPR")

  init(
    githubCLI: GithubCLIClient,
    clock: any Clock<Duration>,
    debounceWindow: Duration = .milliseconds(250),
    softTimeout: Duration = .seconds(6),
    aliasLimit: Int = 15,
    resultHandler: @MainActor @escaping (Outcome) -> Void
  ) {
    self.githubCLI = githubCLI
    self.clock = clock
    self.debounceWindow = debounceWindow
    self.softTimeout = softTimeout
    self.aliasLimit = aliasLimit
    self.resultHandler = resultHandler
  }

  func enqueue(_ request: Request) {
    // Sanitize branches at the gate: silently drop a request that contributes nothing.
    let cleanedBranches = request.branches.filter {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !cleanedBranches.isEmpty else {
      return
    }
    let normalized = Request(
      repositoryID: request.repositoryID,
      repositoryRootURL: request.repositoryRootURL,
      host: request.host,
      owner: request.owner,
      repo: request.repo,
      branches: cleanedBranches,
      worktreeIDs: request.worktreeIDs
    )

    if inflightHosts.contains(normalized.host) {
      // [BPR] remove after manual verification
      logger.debug("queue host=\(normalized.host) repo=\(normalized.owner)/\(normalized.repo) (inflight)")
      mergeRequest(normalized, into: &queuedByHost)
      return
    }

    mergeRequest(normalized, into: &pendingByHost)
    // [BPR] remove after manual verification
    logger.debug("enqueue host=\(normalized.host) repo=\(normalized.owner)/\(normalized.repo)")
    rescheduleDebounce(forHost: normalized.host)
  }

  func cancelHost(_ host: String) {
    flushTaskByHost.removeValue(forKey: host)?.cancel()
    pendingByHost.removeValue(forKey: host)
    queuedByHost.removeValue(forKey: host)
  }

  func reset() {
    for (_, task) in flushTaskByHost {
      task.cancel()
    }
    flushTaskByHost.removeAll()
    pendingByHost.removeAll()
    queuedByHost.removeAll()
    inflightHosts.removeAll()
  }

  private func mergeRequest(
    _ request: Request,
    into bucket: inout [String: [Repository.ID: Request]]
  ) {
    var hostBucket = bucket[request.host] ?? [:]
    if let existing = hostBucket[request.repositoryID] {
      var seen = Set<String>(existing.branches)
      var combined = existing.branches
      for branch in request.branches where seen.insert(branch).inserted {
        combined.append(branch)
      }
      var workseen = Set<Worktree.ID>(existing.worktreeIDs)
      var workCombined = existing.worktreeIDs
      for worktreeID in request.worktreeIDs where workseen.insert(worktreeID).inserted {
        workCombined.append(worktreeID)
      }
      hostBucket[request.repositoryID] = Request(
        repositoryID: request.repositoryID,
        repositoryRootURL: request.repositoryRootURL,
        host: request.host,
        owner: request.owner,
        repo: request.repo,
        branches: combined,
        worktreeIDs: workCombined
      )
    } else {
      hostBucket[request.repositoryID] = request
    }
    bucket[request.host] = hostBucket
  }

  private func rescheduleDebounce(forHost host: String) {
    flushTaskByHost.removeValue(forKey: host)?.cancel()
    let task = Task { [weak self, debounceWindow, clock] in
      do {
        try await clock.sleep(for: debounceWindow)
      } catch {
        return
      }
      await self?.flush(host: host)
    }
    flushTaskByHost[host] = task
  }

  private func flush(host: String) async {
    flushTaskByHost.removeValue(forKey: host)
    guard let bucket = pendingByHost.removeValue(forKey: host), !bucket.isEmpty else {
      return
    }
    inflightHosts.insert(host)
    let requests = Array(bucket.values)
    // [BPR] remove after manual verification
    logger.debug("flush host=\(host) repos=\(requests.count)")
    await processBatch(host: host, requests: requests)
    inflightHosts.remove(host)
    if let queued = queuedByHost.removeValue(forKey: host), !queued.isEmpty {
      pendingByHost[host, default: [:]].merge(queued) { _, new in new }
      // [BPR] remove after manual verification
      logger.debug("drain-queued host=\(host) repos=\(queued.count)")
      await flush(host: host)
    }
  }

  private func processBatch(host: String, requests: [Request]) async {
    let crossRepoRequests = requests.map {
      CrossRepoPullRequestRequest(owner: $0.owner, repo: $0.repo, branches: $0.branches)
    }
    do {
      let result = try await runBatchWithTimeout(host: host, requests: crossRepoRequests)
      let requestsByKey = Dictionary(
        uniqueKeysWithValues: requests.map { (RepoKey(owner: $0.owner, repo: $0.repo), $0) }
      )
      for (key, prsByBranch) in result.successByRepo {
        guard let request = requestsByKey[key] else {
          continue
        }
        resultHandler(
          .refreshed(
            repositoryID: request.repositoryID,
            repositoryRootURL: request.repositoryRootURL,
            worktreeIDs: request.worktreeIDs,
            prsByBranch: prsByBranch
          )
        )
      }
      for (key, _) in result.failedRepos {
        guard let request = requestsByKey[key] else {
          continue
        }
        // [BPR] remove after manual verification
        logger.debug("fallback partial repo=\(key.owner)/\(key.repo)")
        await fallbackPerRepo(request)
      }
    } catch {
      // [BPR] remove after manual verification
      logger.debug("fallback batch host=\(host) error=\(String(describing: error))")
      for request in requests {
        await fallbackPerRepo(request)
      }
    }
  }

  private func runBatchWithTimeout(
    host: String,
    requests: [CrossRepoPullRequestRequest]
  ) async throws -> CrossRepoPullRequestResult {
    try await withThrowingTaskGroup(of: BatchTimeoutOutcome.self) { group in
      let githubCLI = self.githubCLI
      let softTimeout = self.softTimeout
      let clock = self.clock
      group.addTask {
        let value = try await githubCLI.batchPullRequestsAcrossRepositories(host, requests)
        return .completed(value)
      }
      group.addTask {
        try await clock.sleep(for: softTimeout)
        return .timedOut
      }
      defer { group.cancelAll() }
      while let outcome = try await group.next() {
        switch outcome {
        case .completed(let value):
          return value
        case .timedOut:
          throw PullRequestRefreshCoordinatorError.softTimeout
        }
      }
      throw PullRequestRefreshCoordinatorError.softTimeout
    }
  }

  private func fallbackPerRepo(_ request: Request) async {
    do {
      let prs = try await githubCLI.batchPullRequests(
        request.host,
        request.owner,
        request.repo,
        request.branches
      )
      resultHandler(
        .refreshed(
          repositoryID: request.repositoryID,
          repositoryRootURL: request.repositoryRootURL,
          worktreeIDs: request.worktreeIDs,
          prsByBranch: prs
        )
      )
    } catch {
      resultHandler(
        .failed(
          repositoryID: request.repositoryID,
          worktreeIDs: request.worktreeIDs,
          message: String(describing: error)
        )
      )
    }
  }

  private enum BatchTimeoutOutcome: Sendable {
    case completed(CrossRepoPullRequestResult)
    case timedOut
  }
}

enum PullRequestRefreshCoordinatorError: Error, Equatable {
  case softTimeout
}

nonisolated struct PullRequestRefreshCoordinatorClient: Sendable {
  var enqueue: @Sendable (PullRequestRefreshCoordinator.Request) -> Void
  var cancelHost: @Sendable (String) -> Void
  var reset: @Sendable () -> Void

  nonisolated static let unimplemented = PullRequestRefreshCoordinatorClient(
    enqueue: { _ in },
    cancelHost: { _ in },
    reset: {}
  )
}

extension PullRequestRefreshCoordinatorClient: DependencyKey {
  nonisolated static let liveValue = unimplemented
  nonisolated static let testValue = unimplemented
}

extension DependencyValues {
  var pullRequestRefreshCoordinator: PullRequestRefreshCoordinatorClient {
    get { self[PullRequestRefreshCoordinatorClient.self] }
    set { self[PullRequestRefreshCoordinatorClient.self] = newValue }
  }
}
