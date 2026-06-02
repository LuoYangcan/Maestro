import Foundation

struct PaneAgentState: Equatable, Sendable {
  var detectedAgent: DetectedAgent?
  var fallbackState: AgentRawState
  var state: AgentRawState
  var seen: Bool
  var lastChangedAt: Date

  init(
    detectedAgent: DetectedAgent? = nil,
    fallbackState: AgentRawState = .unknown,
    state: AgentRawState = .unknown,
    seen: Bool = true,
    lastChangedAt: Date = Date()
  ) {
    self.detectedAgent = detectedAgent
    self.fallbackState = fallbackState
    self.state = state
    self.seen = seen
    self.lastChangedAt = lastChangedAt
  }

  var displayState: AgentDisplayState {
    switch state {
    case .working:
      return .working
    case .blocked:
      return .blocked
    case .idle:
      return seen ? .idle : .done
    case .unknown:
      return detectedAgent == nil ? .idle : .unknown
    }
  }
}

struct AgentDetectionPresence: Equatable, Sendable {
  static let releaseMissThreshold = 6

  var currentAgent: DetectedAgent?
  var consecutiveMisses: UInt8

  init(currentAgent: DetectedAgent? = nil, consecutiveMisses: UInt8 = 0) {
    self.currentAgent = currentAgent
    self.consecutiveMisses = consecutiveMisses
  }

  mutating func update(detectedAgent: DetectedAgent?) -> DetectedAgent? {
    if let detectedAgent {
      currentAgent = detectedAgent
      consecutiveMisses = 0
      return detectedAgent
    }

    guard currentAgent != nil else {
      consecutiveMisses = 0
      return nil
    }

    consecutiveMisses = min(consecutiveMisses + 1, UInt8(Self.releaseMissThreshold))
    if consecutiveMisses >= Self.releaseMissThreshold {
      currentAgent = nil
      consecutiveMisses = 0
    }
    return currentAgent
  }
}

private let agentWorkingHold: TimeInterval = 1.2
private let agentUnknownHold: TimeInterval = agentWorkingHold

struct AgentStateStabilizationHistory: Equatable, Sendable {
  var lastWorkingAt: Date?
  var lastUnknownAt: Date?

  init(lastWorkingAt: Date? = nil, lastUnknownAt: Date? = nil) {
    self.lastWorkingAt = lastWorkingAt
    self.lastUnknownAt = lastUnknownAt
  }
}

func stabilizeAgentState(
  agent: DetectedAgent?,
  previous: PaneAgentState,
  raw: AgentRawState,
  now: Date,
  history: inout AgentStateStabilizationHistory
) -> AgentRawState {
  guard let agent else {
    history = AgentStateStabilizationHistory()
    return raw
  }
  let previousAgent = previous.detectedAgent
  let isSameAgent = previousAgent == nil || previousAgent == agent
  let previousForAgent = isSameAgent ? previous.state : AgentRawState.unknown
  if !isSameAgent {
    history = AgentStateStabilizationHistory()
  }

  switch raw {
  case .working:
    history.lastWorkingAt = now
    history.lastUnknownAt = nil
    return .working
  case .blocked:
    history.lastUnknownAt = nil
    return .blocked
  case .idle where previousForAgent == .working:
    history.lastUnknownAt = nil
    guard let lastWorkingAt = history.lastWorkingAt else {
      return .idle
    }
    return now.timeIntervalSince(lastWorkingAt) < agentWorkingHold ? .working : .idle
  case .idle:
    history.lastUnknownAt = nil
    return .idle
  case .unknown where previousForAgent == .unknown:
    return .unknown
  case .unknown:
    let firstUnknownAt = history.lastUnknownAt ?? now
    history.lastUnknownAt = firstUnknownAt
    return now.timeIntervalSince(firstUnknownAt) < agentUnknownHold ? previousForAgent : .unknown
  }
}
