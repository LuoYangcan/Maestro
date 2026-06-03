import Foundation

@MainActor
@Observable
final class MemoryWatchdog {
  struct Context: Sendable, Equatable {
    let repositoryCount: Int
    let openedWorktreeCount: Int
    let terminalTabCount: Int
  }

  private let probe: @Sendable () -> Int
  private let clock: @Sendable () -> Date
  private let tickInterval: TimeInterval
  private let baselineDelay: TimeInterval
  private let thresholdsMB: [Int]
  private let warningThresholdMB: Int
  private let contextProvider: @MainActor () -> Context
  private let logger = SupaLogger("MemoryWatchdog")

  private let startedAt: Date
  private(set) var baselineMB: Int?
  private(set) var firedThresholds: Set<Int> = []
  private var tickTask: Task<Void, Never>?

  init(
    probe: @escaping @Sendable () -> Int = MemoryProbe.physFootprintMegabytes,
    clock: @escaping @Sendable () -> Date = Date.init,
    tickInterval: TimeInterval = 300,
    baselineDelay: TimeInterval = 180,
    thresholdsMB: [Int] = [2048, 4096, 8192],
    warningThresholdMB: Int = 4096,
    contextProvider: @escaping @MainActor () -> Context
  ) {
    self.probe = probe
    self.clock = clock
    self.tickInterval = tickInterval
    self.baselineDelay = baselineDelay
    self.thresholdsMB = thresholdsMB.sorted()
    self.warningThresholdMB = warningThresholdMB
    self.contextProvider = contextProvider
    self.startedAt = clock()
  }

  /// Begins periodic ticking on a background Task. Safe to call more than once.
  func start() {
    tickTask?.cancel()
    let interval = tickInterval
    tickTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        self?.tick()
      }
    }
  }

  func stop() {
    tickTask?.cancel()
    tickTask = nil
  }

  /// One monitoring pass. Exposed for tests; `start()` drives it on a schedule.
  func tick() {
    let now = clock()
    let currentMB = probe()
    let uptime = now.timeIntervalSince(startedAt)

    if baselineMB == nil, uptime >= baselineDelay {
      baselineMB = currentMB
      let ctx = contextProvider()
      logger.info(
        logLine(
          event: "app_memory_baseline",
          properties: baselineProperties(
            currentMB: currentMB,
            uptime: uptime,
            context: ctx
          )))
    }

    guard let baseline = baselineMB else { return }

    for threshold in thresholdsMB where currentMB >= threshold && !firedThresholds.contains(threshold) {
      firedThresholds.insert(threshold)
      let ctx = contextProvider()
      let event = "memory_threshold_\(threshold)mb"
      let props = thresholdProperties(
        currentMB: currentMB,
        baselineMB: baseline,
        uptime: uptime,
        context: ctx
      )
      let line = logLine(event: event, properties: props)
      if threshold >= warningThresholdMB {
        logger.warning(line)
      } else {
        logger.info(line)
      }
    }
  }

  private func baselineProperties(currentMB: Int, uptime: TimeInterval, context: Context) -> [String: String] {
    [
      "resident_mb": "\(currentMB)",
      "uptime_seconds": "\(Int(uptime))",
      "repository_count": "\(context.repositoryCount)",
      "opened_worktree_count": "\(context.openedWorktreeCount)",
      "terminal_tab_count": "\(context.terminalTabCount)",
    ]
  }

  private func thresholdProperties(
    currentMB: Int,
    baselineMB: Int,
    uptime: TimeInterval,
    context: Context
  ) -> [String: String] {
    let growth = baselineMB > 0 ? (Double(currentMB) / Double(baselineMB)) : 0
    return [
      "resident_mb": "\(currentMB)",
      "baseline_mb": "\(baselineMB)",
      "growth_ratio": "\((growth * 100).rounded() / 100)",
      "uptime_seconds": "\(Int(uptime))",
      "repository_count": "\(context.repositoryCount)",
      "opened_worktree_count": "\(context.openedWorktreeCount)",
      "terminal_tab_count": "\(context.terminalTabCount)",
    ]
  }

  private func logLine(event: String, properties: [String: String]) -> String {
    let values = properties.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    return ([event] + values).joined(separator: " ")
  }
}
