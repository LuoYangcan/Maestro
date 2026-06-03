import Foundation

struct ActiveAgentEntry: Identifiable, Equatable, Sendable {
  let id: UUID
  /// The worktree that physically owns the agent's terminal surface (the tab's worktree).
  /// Drives navigation/focus (`focusSurface`/`selectWorktree`), so it must stay the surface's
  /// real owner even when the agent runs in a different directory. Display name/branch come from
  /// `workingDirectory` instead — see `SidebarListView.activeAgentRowDisplay`.
  let worktreeID: Worktree.ID
  let worktreeName: String
  /// The agent's current working directory at detection time, used to resolve the displayed
  /// repository/branch. `nil` when the terminal hasn't reported a directory, in which case the
  /// display falls back to `worktreeID`/`worktreeName`.
  let workingDirectory: URL?
  let tabID: TerminalTabID
  let tabTitle: String
  let surfaceID: UUID
  let paneIndex: Int
  let agent: DetectedAgent
  let rawState: AgentRawState
  let displayState: AgentDisplayState
  let lastChangedAt: Date
}
