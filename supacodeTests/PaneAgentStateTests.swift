import Foundation
import Testing

@testable import supacode

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

  @Test func displayStateDistinguishesIndeterminateAgentFromNoAgent() {
    #expect(PaneAgentState(state: .unknown).displayState == .idle)
    #expect(PaneAgentState(detectedAgent: .claude, state: .unknown).displayState == .unknown)
  }

  @Test func claudeWorkingIsStickyForShortIdleGap() {
    let now = Date(timeIntervalSince1970: 100)
    var history = AgentStateStabilizationHistory()

    let working = stabilizeAgentState(
      agent: .claude,
      previous: PaneAgentState(detectedAgent: .claude, state: .idle),
      raw: .working,
      now: now,
      history: &history
    )
    #expect(working == .working)

    let stillWorking = stabilizeAgentState(
      agent: .claude,
      previous: PaneAgentState(detectedAgent: .claude, state: .working),
      raw: .idle,
      now: now.addingTimeInterval(0.4),
      history: &history
    )
    #expect(stillWorking == .working)
  }

  @Test func claudeTransitionsToIdleAfterStickyWindow() {
    let now = Date(timeIntervalSince1970: 100)
    var history = AgentStateStabilizationHistory(lastWorkingAt: now)

    let idle = stabilizeAgentState(
      agent: .claude,
      previous: PaneAgentState(detectedAgent: .claude, state: .working),
      raw: .idle,
      now: now.addingTimeInterval(1.201),
      history: &history
    )

    #expect(idle == .idle)
  }

  @Test func codexWorkingIsStickyForShortIdleGap() {
    let now = Date(timeIntervalSince1970: 100)
    var history = AgentStateStabilizationHistory(lastWorkingAt: now)

    let working = stabilizeAgentState(
      agent: .codex,
      previous: PaneAgentState(detectedAgent: .codex, state: .working),
      raw: .idle,
      now: now.addingTimeInterval(0.4),
      history: &history
    )

    #expect(working == .working)
    #expect(history.lastWorkingAt == now)
  }

  @Test func singleUnknownFrameHoldsPreviousState() {
    let now = Date(timeIntervalSince1970: 100)
    var history = AgentStateStabilizationHistory(lastWorkingAt: now)

    let stabilized = stabilizeAgentState(
      agent: .claude,
      previous: PaneAgentState(detectedAgent: .claude, state: .working),
      raw: .unknown,
      now: now.addingTimeInterval(0.1),
      history: &history
    )

    #expect(stabilized == .working)
    #expect(history.lastUnknownAt == now.addingTimeInterval(0.1))
  }

  @Test func sustainedUnknownTransitionsToUnknownAfterHoldWindow() {
    let now = Date(timeIntervalSince1970: 100)
    var history = AgentStateStabilizationHistory(lastWorkingAt: now, lastUnknownAt: now)

    let stabilized = stabilizeAgentState(
      agent: .claude,
      previous: PaneAgentState(detectedAgent: .claude, state: .working),
      raw: .unknown,
      now: now.addingTimeInterval(1.201),
      history: &history
    )

    #expect(stabilized == .unknown)
  }

  @Test func workingUnknownJitterDoesNotFlipDisplayState() {
    let now = Date(timeIntervalSince1970: 100)
    var history = AgentStateStabilizationHistory()

    let working = stabilizeAgentState(
      agent: .claude,
      previous: PaneAgentState(detectedAgent: .claude, state: .idle),
      raw: .working,
      now: now,
      history: &history
    )
    #expect(working == .working)

    let held = stabilizeAgentState(
      agent: .claude,
      previous: PaneAgentState(detectedAgent: .claude, state: .working),
      raw: .unknown,
      now: now.addingTimeInterval(0.3),
      history: &history
    )
    #expect(held == .working)

    let recovered = stabilizeAgentState(
      agent: .claude,
      previous: PaneAgentState(detectedAgent: .claude, state: .working),
      raw: .working,
      now: now.addingTimeInterval(0.6),
      history: &history
    )
    #expect(recovered == .working)
    #expect(history.lastUnknownAt == nil)
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
