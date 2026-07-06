import Dependencies
import Foundation
import IdentifiedCollections
import Testing

@testable import Maestro

@Suite struct ActiveAgentRowDisplayResolverTests {
  // MARK: - Golden path

  @Test func registeredAncestorWorkingDirectoryShowsResolvedWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "active-agents-worktree-branch",
      workingDirectory: repositoryRoot
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == repositoryRoot.lastPathComponent)
    #expect(display.branchName == "main")
  }

  @Test func workingDirectoryInsideOwningWorktreeShowsOwningWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "active-agents-worktree-branch",
      workingDirectory: childWorktreeDirectory.appending(path: "Sources/Feature")
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "active-agents-worktree-branch")
    #expect(display.branchName == "codex/fix-active-agents-worktree-branch")
  }

  @Test func workingDirectoryInUnrelatedRepoShowsThatRepo() {
    let repositories = repositoriesWithTwoRepos()
    let entry = entry(
      owningWorktreeID: repoAWorktreeID,
      owningWorktreeName: "repo-a-feature",
      workingDirectory: repoBWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == repoBWorktreeDirectory.lastPathComponent)
    #expect(display.branchName == "repo-b-feature")
  }

  @Test func workingDirectoryInSiblingWorktreeShowsResolvedWorktree() {
    let repositories = repositoriesWithTwoSiblingWorktrees()
    let entry = entry(
      owningWorktreeID: siblingWorktreeAID,
      owningWorktreeName: "feat-a",
      workingDirectory: siblingWorktreeBDirectory
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "feat-b")
    #expect(display.branchName == "feat-b")
  }

  @Test func workingDirectoryInRegisteredChildWorktreeShowsResolvedWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: "main-worktree",
      owningWorktreeName: "main",
      workingDirectory: childWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "active-agents-worktree-branch")
    #expect(display.branchName == "codex/fix-active-agents-worktree-branch")
  }

  // MARK: - Boundary

  @Test func nilWorkingDirectoryFallsBackToOwningWorktreeMetadata() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "stale-name",
      workingDirectory: nil
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "active-agents-worktree-branch")
    #expect(display.branchName == "codex/fix-active-agents-worktree-branch")
  }

  @Test func workingDirectoryEqualToOwningWorktreeShowsOwningWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "active-agents-worktree-branch",
      workingDirectory: childWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "active-agents-worktree-branch")
    #expect(display.branchName == "codex/fix-active-agents-worktree-branch")
  }

  @Test func workingDirectoryOutsideAllReposShowsOwningWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let outside = URL(fileURLWithPath: "/Users/someone/Downloads")
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "active-agents-worktree-branch",
      workingDirectory: outside
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "active-agents-worktree-branch")
    #expect(display.branchName == "codex/fix-active-agents-worktree-branch")
  }

  @Test func owningWorktreeNotFoundKeepsResolvedWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: "non-existent-worktree-id",
      owningWorktreeName: "ghost",
      workingDirectory: repositoryRoot
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == repositoryRoot.lastPathComponent)
    #expect(display.branchName == "main")
  }

  @Test func plainFolderOwnerDoesNotOverrideResolvedWorktree() {
    let outerWorktreeDir = URL(fileURLWithPath: "/work/outer")
    let plainFolderDir = outerWorktreeDir.appending(path: "nested-folder")

    let gitRepo = Repository(
      id: "git-outer",
      rootURL: outerWorktreeDir,
      name: "outer",
      kind: .git,
      worktrees: [
        Worktree(
          id: "outer-wt",
          name: "outer-main",
          detail: "detail",
          workingDirectory: outerWorktreeDir,
          repositoryRootURL: outerWorktreeDir
        )
      ]
    )
    let plainRepo = Repository(
      id: "plain-folder",
      rootURL: plainFolderDir,
      name: "Nested Folder",
      kind: .plain,
      worktrees: []
    )
    let repositories = IdentifiedArray(uniqueElements: [gitRepo, plainRepo])

    let entry = entry(
      owningWorktreeID: "plain-folder",
      owningWorktreeName: "Nested Folder",
      workingDirectory: outerWorktreeDir
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "outer")
    #expect(display.branchName == "outer-main")
  }

  // MARK: - Sorter / display consistency

  @Test func sortKeyMatchesDisplayInDescendantLayout() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: "main-worktree",
      owningWorktreeName: "main",
      workingDirectory: childWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)
    let sortKey = sortKey(for: entry, repositories: repositories)

    #expect(sortKey.worktreeName == display.titleName)
    #expect(sortKey.branchName == display.branchName)
  }

  @Test func sortKeyMatchesDisplayInCrossRepoLayout() {
    let repositories = repositoriesWithTwoRepos()
    let entry = entry(
      owningWorktreeID: repoAWorktreeID,
      owningWorktreeName: "repo-a-feature",
      workingDirectory: repoBWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)
    let sortKey = sortKey(for: entry, repositories: repositories)

    #expect(sortKey.worktreeName == display.titleName)
    #expect(sortKey.branchName == display.branchName)
  }

  // MARK: - Fixtures

  private let repositoryRoot = URL(fileURLWithPath: "/work/today-platform-ios")
  private let childWorktreeID = "active-agents-worktree-branch"
  private var childWorktreeDirectory: URL {
    repositoryRoot.appending(path: ".worktrees/active-agents-worktree-branch")
  }

  /// A single git repo whose main worktree is the repo root and whose child worktree lives under
  /// `.worktrees/`.
  private func repositoriesWithMainAndChildWorktree() -> IdentifiedArrayOf<Repository> {
    let repository = Repository(
      id: "today-platform-ios",
      rootURL: repositoryRoot,
      name: "today-platform-ios",
      kind: .git,
      worktrees: [
        Worktree(
          id: "main-worktree",
          name: "main",
          detail: "detail",
          workingDirectory: repositoryRoot,
          repositoryRootURL: repositoryRoot
        ),
        Worktree(
          id: childWorktreeID,
          name: "codex/fix-active-agents-worktree-branch",
          detail: "detail",
          workingDirectory: childWorktreeDirectory,
          repositoryRootURL: repositoryRoot
        ),
      ]
    )
    return IdentifiedArray(uniqueElements: [repository])
  }

  private let siblingWorktreeAID = "feat-a-id"
  private let siblingWorktreeBID = "feat-b-id"
  private var siblingWorktreeADirectory: URL {
    URL(fileURLWithPath: "/work/repo/.worktrees/feat-a")
  }
  private var siblingWorktreeBDirectory: URL {
    URL(fileURLWithPath: "/work/repo/.worktrees/feat-b")
  }

  /// A single git repo with two parallel `.worktrees/` siblings.
  private func repositoriesWithTwoSiblingWorktrees() -> IdentifiedArrayOf<Repository> {
    let repository = Repository(
      id: "repo",
      rootURL: URL(fileURLWithPath: "/work/repo"),
      name: "repo",
      kind: .git,
      worktrees: [
        Worktree(
          id: siblingWorktreeAID,
          name: "feat-a",
          detail: "detail",
          workingDirectory: siblingWorktreeADirectory,
          repositoryRootURL: URL(fileURLWithPath: "/work/repo")
        ),
        Worktree(
          id: siblingWorktreeBID,
          name: "feat-b",
          detail: "detail",
          workingDirectory: siblingWorktreeBDirectory,
          repositoryRootURL: URL(fileURLWithPath: "/work/repo")
        ),
      ]
    )
    return IdentifiedArray(uniqueElements: [repository])
  }

  private let repoAWorktreeID = "repo-a-feature"
  private var repoAWorktreeDirectory: URL {
    URL(fileURLWithPath: "/work/repo-a/.worktrees/feature")
  }
  private var repoBWorktreeDirectory: URL {
    URL(fileURLWithPath: "/work/repo-b/.worktrees/feature")
  }

  /// Two unrelated git repos, each with a worktree. Neither directory tree is an ancestor of the
  /// other.
  private func repositoriesWithTwoRepos() -> IdentifiedArrayOf<Repository> {
    let repoA = Repository(
      id: "repo-a",
      rootURL: URL(fileURLWithPath: "/work/repo-a"),
      name: "repo-a",
      kind: .git,
      worktrees: [
        Worktree(
          id: repoAWorktreeID,
          name: "repo-a-feature",
          detail: "detail",
          workingDirectory: repoAWorktreeDirectory,
          repositoryRootURL: URL(fileURLWithPath: "/work/repo-a")
        )
      ]
    )
    let repoB = Repository(
      id: "repo-b",
      rootURL: URL(fileURLWithPath: "/work/repo-b"),
      name: "repo-b",
      kind: .git,
      worktrees: [
        Worktree(
          id: "repo-b-feature-id",
          name: "repo-b-feature",
          detail: "detail",
          workingDirectory: repoBWorktreeDirectory,
          repositoryRootURL: URL(fileURLWithPath: "/work/repo-b")
        )
      ]
    )
    return IdentifiedArray(uniqueElements: [repoA, repoB])
  }

  private func entry(
    owningWorktreeID: Worktree.ID,
    owningWorktreeName: String,
    workingDirectory: URL?
  ) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: UUID(0),
      worktreeID: owningWorktreeID,
      worktreeName: owningWorktreeName,
      workingDirectory: workingDirectory,
      tabID: TerminalTabID(rawValue: UUID()),
      tabTitle: "1",
      surfaceID: UUID(0),
      paneIndex: 1,
      agent: .codex,
      rawState: .working,
      displayState: .working,
      lastChangedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private func display(
    for entry: ActiveAgentEntry,
    repositories: IdentifiedArrayOf<Repository>
  ) -> ActiveAgentRowDisplay {
    let metadata = ActiveAgentRowDisplayResolver.worktreeMetadata(
      repositories: repositories,
      customTitles: [:]
    )
    return ActiveAgentRowDisplayResolver.display(
      for: entry,
      repositories: repositories,
      metadata: metadata
    )
  }

  private func sortKey(
    for entry: ActiveAgentEntry,
    repositories: IdentifiedArrayOf<Repository>
  ) -> ActiveAgentEntrySorter.SortKey {
    let metadata = ActiveAgentRowDisplayResolver.worktreeMetadata(
      repositories: repositories,
      customTitles: [:]
    )
    return ActiveAgentEntrySorter.sortKey(
      for: entry,
      repositories: repositories,
      metadata: metadata,
      creationSeqBySurfaceID: [:]
    )
  }
}
