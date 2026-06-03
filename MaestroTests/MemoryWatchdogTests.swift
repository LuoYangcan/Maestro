import ConcurrencyExtras
import Foundation
import Testing

@testable import Maestro

@MainActor
struct MemoryWatchdogTests {
  @Test func baselineDoesNotFireBeforeDelay() {
    let env = makeEnv(baselineMB: 500)
    env.now.setValue(baseDate.addingTimeInterval(60))
    env.watchdog.tick()
    #expect(env.watchdog.baselineMB == nil)
    #expect(env.watchdog.firedThresholds.isEmpty)
  }

  @Test func baselineFiresAtDelayAndOnlyOnce() {
    let env = makeEnv(baselineMB: 500)
    env.now.setValue(baseDate.addingTimeInterval(180))
    env.watchdog.tick()
    #expect(env.watchdog.baselineMB == 500)

    env.currentMB.setValue(600)
    env.now.setValue(baseDate.addingTimeInterval(600))
    env.watchdog.tick()
    #expect(env.watchdog.baselineMB == 500, "baseline must not be overwritten")
  }

  @Test func thresholdFiresOnceEach() {
    let env = makeEnv(baselineMB: 500)
    env.now.setValue(baseDate.addingTimeInterval(180))
    env.watchdog.tick()

    env.currentMB.setValue(2_500)
    env.now.setValue(baseDate.addingTimeInterval(3_600))
    env.watchdog.tick()
    env.currentMB.setValue(5_000)
    env.now.setValue(baseDate.addingTimeInterval(7_200))
    env.watchdog.tick()
    env.currentMB.setValue(9_000)
    env.now.setValue(baseDate.addingTimeInterval(10_800))
    env.watchdog.tick()

    #expect(env.watchdog.firedThresholds == [2_048, 4_096, 8_192])

    env.watchdog.tick()
    #expect(env.watchdog.firedThresholds == [2_048, 4_096, 8_192], "thresholds must not re-fire")
  }

  @Test func droppingBelowThresholdDoesNotRearm() {
    let env = makeEnv(baselineMB: 500)
    env.now.setValue(baseDate.addingTimeInterval(180))
    env.watchdog.tick()

    env.currentMB.setValue(2_500)
    env.now.setValue(baseDate.addingTimeInterval(3_600))
    env.watchdog.tick()
    env.currentMB.setValue(800)
    env.now.setValue(baseDate.addingTimeInterval(7_200))
    env.watchdog.tick()
    env.currentMB.setValue(2_500)
    env.now.setValue(baseDate.addingTimeInterval(10_800))
    env.watchdog.tick()

    #expect(env.watchdog.firedThresholds == [2_048])
  }

  @Test func thresholdsNeverFireWithoutBaseline() {
    let env = makeEnv(baselineMB: 3_000)
    env.now.setValue(baseDate.addingTimeInterval(30))
    env.watchdog.tick()
    #expect(env.watchdog.baselineMB == nil)
    #expect(env.watchdog.firedThresholds.isEmpty)
  }

  @Test func crossingMultipleThresholdsInOneTickMarksEachThreshold() {
    let env = makeEnv(baselineMB: 500)
    env.now.setValue(baseDate.addingTimeInterval(180))
    env.watchdog.tick()

    env.currentMB.setValue(5_000)
    env.now.setValue(baseDate.addingTimeInterval(3_600))
    env.watchdog.tick()

    #expect(env.watchdog.firedThresholds == [2_048, 4_096])
  }

  // MARK: - Test helpers

  private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

  private struct Env {
    let watchdog: MemoryWatchdog
    let currentMB: LockIsolated<Int>
    let now: LockIsolated<Date>
  }

  private func makeEnv(baselineMB: Int) -> Env {
    let currentMB = LockIsolated(baselineMB)
    let now = LockIsolated(baseDate)
    let watchdog = MemoryWatchdog(
      probe: { currentMB.value },
      clock: { now.value },
      tickInterval: 300,
      baselineDelay: 180,
      thresholdsMB: [2_048, 4_096, 8_192],
      warningThresholdMB: 4_096,
      contextProvider: {
        .init(repositoryCount: 1, openedWorktreeCount: 2, terminalTabCount: 3)
      }
    )
    return Env(
      watchdog: watchdog,
      currentMB: currentMB,
      now: now
    )
  }
}
