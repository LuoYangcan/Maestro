enum LaunchRestoreMode: Equatable, Sendable {
  case lastFocusedWorktree
  case restoreLayout
  /// Cold-launch path passed from `maestro open`.
  /// When set, startup should avoid restoring last focused worktree first.
  case cliOpenPath(String)
}
