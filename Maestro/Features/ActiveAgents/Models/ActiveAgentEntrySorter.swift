import Foundation
import IdentifiedCollections

/// Orders active agents by their displayed grouping — repository, then worktree, then branch —
/// using the same display-name resolution the rows render (`ActiveAgentRowDisplayResolver`), so the
/// list order matches the labels users see. Comparisons use `localizedStandardCompare` for natural
/// numeric ordering (`feat-2` before `feat-10`). Within an identical display group agents order by
/// `creationSeq` (earlier-created first); `surfaceID` is the final deterministic tie-break, used
/// only as a stability guard so equal keys never reorder between runs.
enum ActiveAgentEntrySorter {
  /// The display-derived ordering key for one agent. `repositoryName` is empty only when the
  /// resolved (owning-corrected) worktree id has no metadata entry; equal empty keys still order
  /// deterministically through the lower tiers. `creationSeq` is the monotonic first-appearance
  /// order from `ActiveAgentsFeature.State.creationSeqBySurfaceID` (smaller = created earlier).
  struct SortKey: Equatable {
    let repositoryName: String
    let worktreeName: String
    let branchName: String
    let creationSeq: Int
    let surfaceID: UUID
  }

  static func sorted(
    entries: IdentifiedArrayOf<ActiveAgentEntry>,
    repositories: IdentifiedArrayOf<Repository>,
    metadata: ActiveAgentWorktreeMetadata,
    creationSeqBySurfaceID: [UUID: Int]
  ) -> IdentifiedArrayOf<ActiveAgentEntry> {
    guard entries.count > 1 else { return entries }
    let result = entries.sorted { lhs, rhs in
      isOrderedBefore(
        sortKey(
          for: lhs,
          repositories: repositories,
          metadata: metadata,
          creationSeqBySurfaceID: creationSeqBySurfaceID
        ),
        sortKey(
          for: rhs,
          repositories: repositories,
          metadata: metadata,
          creationSeqBySurfaceID: creationSeqBySurfaceID
        )
      )
    }
    return IdentifiedArray(uniqueElements: result)
  }

  /// Builds the `(repository, worktree, branch, creationSeq)` key for an entry. The three names are
  /// read from the *same* worktree id the row label uses — `ActiveAgentRowDisplayResolver`'s shared
  /// `displayWorktreeID(for:in:)`, which applies the owning-worktree correction — so the sort group
  /// can never drift from the label a user sees. `creationSeq` falls back to `Int.max` when the
  /// surface is absent from the map so an un-tracked agent sorts last within its group rather than
  /// jumping ahead (normally every entry is tracked).
  static func sortKey(
    for entry: ActiveAgentEntry,
    repositories: IdentifiedArrayOf<Repository>,
    metadata: ActiveAgentWorktreeMetadata,
    creationSeqBySurfaceID: [UUID: Int]
  ) -> SortKey {
    let creationSeq = creationSeqBySurfaceID[entry.surfaceID] ?? Int.max
    let key = ActiveAgentRowDisplayResolver.displayWorktreeID(for: entry, in: repositories)
    let fallbackName = entry.workingDirectory?.lastPathComponent ?? entry.worktreeName
    return SortKey(
      repositoryName: metadata.repositoryNamesByWorktreeID[key] ?? "",
      worktreeName: metadata.worktreeDirectoryNamesByWorktreeID[key] ?? fallbackName,
      branchName: metadata.branchNamesByWorktreeID[key] ?? fallbackName,
      creationSeq: creationSeq,
      surfaceID: entry.surfaceID
    )
  }

  /// Three-tier natural-order comparison, short-circuiting on the first non-equal tier, then
  /// ordering by integer `creationSeq` (earlier-created first) and finally falling back to
  /// `surfaceID` so the result is total and stable.
  static func isOrderedBefore(_ lhs: SortKey, _ rhs: SortKey) -> Bool {
    for (left, right) in [
      (lhs.repositoryName, rhs.repositoryName),
      (lhs.worktreeName, rhs.worktreeName),
      (lhs.branchName, rhs.branchName),
    ] {
      switch left.localizedStandardCompare(right) {
      case .orderedAscending: return true
      case .orderedDescending: return false
      case .orderedSame: continue
      }
    }
    if lhs.creationSeq != rhs.creationSeq {
      return lhs.creationSeq < rhs.creationSeq
    }
    return lhs.surfaceID.uuidString.localizedStandardCompare(rhs.surfaceID.uuidString) == .orderedAscending
  }
}
