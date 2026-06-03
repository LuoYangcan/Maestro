import Foundation
import Testing

@testable import Maestro

struct PaneAgentStateTests {
  @Test func displayStateDerivesDoneFromUnseenIdle() {
    var state = PaneAgentState(
      detectedAgent: .codex,
      fallbackState: .idle,
      state: .idle,
      seen: false,
      lastChangedAt: Date(timeIntervalSince1970: 0)
    )

    #expect(state.displayState == .done)
    state.seen = true
    #expect(state.displayState == .idle)
  }

  @Test func claudeWorkingIsStickyForShortIdleGap() {
    let now = Date(timeIntervalSince1970: 100)
    var lastWorking: Date?

    let working = stabilizeAgentState(
      agent: .claude,
      previous: .idle,
      raw: .working,
      now: now,
      lastClaudeWorkingAt: &lastWorking
    )
    #expect(working == .working)

    let stillWorking = stabilizeAgentState(
      agent: .claude,
      previous: .working,
      raw: .idle,
      now: now.addingTimeInterval(0.4),
      lastClaudeWorkingAt: &lastWorking
    )
    #expect(stillWorking == .working)
  }

  @Test func claudeTransitionsToIdleAfterStickyWindow() {
    let now = Date(timeIntervalSince1970: 100)
    var lastWorking: Date? = now

    let idle = stabilizeAgentState(
      agent: .claude,
      previous: .working,
      raw: .idle,
      now: now.addingTimeInterval(1.201),
      lastClaudeWorkingAt: &lastWorking
    )

    #expect(idle == .idle)
  }

  @Test func nonClaudeDoesNotUseStickyWindow() {
    let now = Date(timeIntervalSince1970: 100)
    var lastWorking: Date? = now

    let idle = stabilizeAgentState(
      agent: .codex,
      previous: .working,
      raw: .idle,
      now: now,
      lastClaudeWorkingAt: &lastWorking
    )

    #expect(idle == .idle)
    #expect(lastWorking == nil)
  }

  @Test func presenceRequiresSixMissesBeforeRelease() {
    var presence = AgentDetectionPresence(currentAgent: .codex)

    for _ in 0..<5 {
      #expect(presence.update(detectedAgent: nil) == .codex)
    }
    #expect(presence.update(detectedAgent: nil) == nil)
    #expect(presence.currentAgent == nil)
  }
}
