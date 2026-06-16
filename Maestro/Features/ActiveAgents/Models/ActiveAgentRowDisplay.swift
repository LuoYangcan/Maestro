import Foundation
import IdentifiedCollections

enum ActiveAgentRowDisplayResolver {
  static func worktreeMetadata(
    repositories: IdentifiedArrayOf<Repository>,
    customTitles: [Repository.ID: String],
    repositoryAppearances: [Repository.ID: RepositoryAppearance] = [:]
  ) -> ActiveAgentWorktreeMetadata {
    var repositoryNamesByWorktreeID: [Worktree.ID: String] = [:]
    var worktreeDirectoryNamesByWorktreeID: [Worktree.ID: String] = [:]
    var branchNamesByWorktreeID: [Worktree.ID: String] = [:]
    var repositoryColorsByWorktreeID: [Worktree.ID: RepositoryColorChoice] = [:]

    for repository in repositories {
      let repositoryName = customTitles[repository.id] ?? repository.name
      let repositoryColor = repositoryAppearances[repository.id]?.color
      if repository.capabilities.supportsRunnableFolderActions && !repository.capabilities.supportsWorktrees {
        repositoryNamesByWorktreeID[repository.id] = repositoryName
        worktreeDirectoryNamesByWorktreeID[repository.id] = repository.rootURL.lastPathComponent
        branchNamesByWorktreeID[repository.id] = repository.name
        if let repositoryColor {
          repositoryColorsByWorktreeID[repository.id] = repositoryColor
        }
      }
      for worktree in repository.worktrees {
        repositoryNamesByWorktreeID[worktree.id] = repositoryName
        worktreeDirectoryNamesByWorktreeID[worktree.id] = worktree.workingDirectory.lastPathComponent
        branchNamesByWorktreeID[worktree.id] = worktree.name
        if let repositoryColor {
          repositoryColorsByWorktreeID[worktree.id] = repositoryColor
        }
      }
    }

    return ActiveAgentWorktreeMetadata(
      repositoryNamesByWorktreeID: repositoryNamesByWorktreeID,
      worktreeDirectoryNamesByWorktreeID: worktreeDirectoryNamesByWorktreeID,
      branchNamesByWorktreeID: branchNamesByWorktreeID,
      repositoryColorsByWorktreeID: repositoryColorsByWorktreeID
    )
  }

  /// Resolves the repository/branch label shown for each active agent from the directory the
  /// agent actually runs in, rather than the tab's owning worktree.
  static func displays(
    entries: IdentifiedArrayOf<ActiveAgentEntry>,
    repositories: IdentifiedArrayOf<Repository>,
    metadata: ActiveAgentWorktreeMetadata
  ) -> [ActiveAgentEntry.ID: ActiveAgentRowDisplay] {
    var displays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay] = [:]
    for entry in entries {
      displays[entry.id] = display(
        for: entry,
        repositories: repositories,
        metadata: metadata
      )
    }
    return displays
  }

  /// Resolution for the displayed name/branch of a single agent. The worktree id whose metadata is
  /// shown comes from the shared `displayWorktreeID(for:in:)` resolver so the row label and the sort
  /// key (`ActiveAgentEntrySorter`) can never disagree. `fallbackName` is only reachable when
  /// `displayWorktreeID` returns a tier-1 resolved worktree id that is absent from `metadata` (stale
  /// snapshot); in tier-2 and tier-3 the resolver returns `entry.worktreeID` whose owning worktree
  /// always has a metadata entry, so the `??` never fires on those paths.
  static func display(
    for entry: ActiveAgentEntry,
    repositories: IdentifiedArrayOf<Repository>,
    metadata: ActiveAgentWorktreeMetadata
  ) -> ActiveAgentRowDisplay {
    let displayKey = displayWorktreeID(for: entry, in: repositories)
    let fallbackName = entry.workingDirectory?.lastPathComponent ?? entry.worktreeName
    return ActiveAgentRowDisplay(
      titleName: metadata.worktreeDirectoryNamesByWorktreeID[displayKey] ?? fallbackName,
      branchName: metadata.branchNamesByWorktreeID[displayKey] ?? fallbackName,
      color: metadata.repositoryColorsByWorktreeID[displayKey]
    )
  }

  /// The single worktree id whose metadata both the row label and the sort key read from, so they
  /// stay in lockstep. Three tiers:
  /// 1. `workingDirectory` resolves to a known worktree → that worktree, corrected toward the
  ///    owning worktree whenever both live in the same repository (`displayWorktreeID(resolved:owning:in:)`).
  /// 2. `workingDirectory` is known but resolves to nothing (it sits outside every registered repo,
  ///    so it is not "a different repo") → the owning worktree.
  /// 3. `workingDirectory` is unknown → the owning worktree.
  static func displayWorktreeID(
    for entry: ActiveAgentEntry,
    in repositories: IdentifiedArrayOf<Repository>
  ) -> Worktree.ID {
    guard
      let workingDirectory = entry.workingDirectory,
      let resolved = resolveWorktreeID(forWorkingDirectory: workingDirectory, in: repositories)
    else {
      return entry.worktreeID
    }
    return displayWorktreeID(resolved: resolved, owning: entry.worktreeID, in: repositories)
  }

  /// Picks which worktree id to display once the agent's cwd has resolved to `resolved`: the
  /// tab's `owning` worktree wins whenever both belong to the same repository — no matter whether
  /// `resolved` is the owner itself, an ancestor, a descendant, a sibling, or a cousin — because the
  /// row identifies the tab, not wherever the agent process happened to `cd`. `resolved` is kept
  /// when the agent has genuinely moved into a *different* repository. The lone exception is a
  /// directory that merely *contains* the owning worktree on disk (e.g. the owning target is a plain
  /// folder nested inside an outer git worktree): such a strict ancestor isn't a different project
  /// the user navigated to, so the more-specific owning worktree still wins. When either id can't be
  /// mapped to a repository there is no basis for the comparison, so `resolved` stays.
  private static func displayWorktreeID(
    resolved: Worktree.ID,
    owning: Worktree.ID,
    in repositories: IdentifiedArrayOf<Repository>
  ) -> Worktree.ID {
    guard
      let resolvedRepository = repositoryID(forWorktreeID: resolved, in: repositories),
      let owningRepository = repositoryID(forWorktreeID: owning, in: repositories)
    else {
      return resolved
    }
    if resolvedRepository == owningRepository {
      return owning
    }
    guard
      let ownerDir = directory(forWorktreeID: owning, in: repositories),
      let resolvedDir = directory(forWorktreeID: resolved, in: repositories)
    else {
      return resolved
    }
    let resolvedIsStrictAncestor =
      PathPolicy.contains(ownerDir, in: resolvedDir)
      && !PathPolicy.contains(resolvedDir, in: ownerDir)
    return resolvedIsStrictAncestor ? owning : resolved
  }

  /// Looks up the on-disk directory backing a worktree id. Plain folders are keyed by their
  /// repository id (directory is the repo root); git repos are matched through their worktrees.
  ///
  /// **Invariant**: the keying scheme here (plain-folder → `repository.id`, git → `worktree.id`)
  /// must stay identical to `worktreeMetadata(...)`, `resolveWorktreeID(forWorkingDirectory:in:)`,
  /// and `repositoryID(forWorktreeID:in:)`. Changing the key in any one of those functions without
  /// updating the others will silently desync them and produce incorrect same-repo comparisons or
  /// missing metadata lookups.
  private static func directory(
    forWorktreeID id: Worktree.ID,
    in repositories: IdentifiedArrayOf<Repository>
  ) -> URL? {
    for repository in repositories {
      if repository.id == id,
        repository.capabilities.supportsRunnableFolderActions,
        !repository.capabilities.supportsWorktrees
      {
        return repository.rootURL
      }
      if let worktree = repository.worktrees[id: id] {
        return worktree.workingDirectory
      }
    }
    return nil
  }

  /// Finds which repository a worktree id belongs to. The loop structure is intentionally isomorphic
  /// to `directory(forWorktreeID:in:)` (plain-folder → `repository.id`, git → `worktree.id`) so
  /// both functions stay in lockstep — any keying change in one must be mirrored in the other.
  /// Used to decide whether a resolved worktree and the owning worktree share a repository.
  private static func repositoryID(
    forWorktreeID id: Worktree.ID,
    in repositories: IdentifiedArrayOf<Repository>
  ) -> Repository.ID? {
    for repository in repositories {
      if repository.id == id,
        repository.capabilities.supportsRunnableFolderActions,
        !repository.capabilities.supportsWorktrees
      {
        return repository.id
      }
      if repository.worktrees[id: id] != nil {
        return repository.id
      }
    }
    return nil
  }

  /// Finds the most specific repo/worktree whose directory contains `workingDirectory`. Plain
  /// folders are keyed by their repository id; git repos are matched through their worktrees.
  /// When nested directories both match, the deepest one wins.
  static func resolveWorktreeID(
    forWorkingDirectory workingDirectory: URL,
    in repositories: IdentifiedArrayOf<Repository>
  ) -> Worktree.ID? {
    var best: (id: Worktree.ID, depth: Int)?
    func consider(id: Worktree.ID, directory: URL) {
      guard PathPolicy.contains(workingDirectory, in: directory) else { return }
      let depth = PathPolicy.normalizeURL(directory).pathComponents.count
      if let current = best, current.depth >= depth { return }
      best = (id, depth)
    }
    for repository in repositories {
      if repository.capabilities.supportsRunnableFolderActions, !repository.capabilities.supportsWorktrees {
        consider(id: repository.id, directory: repository.rootURL)
      }
      for worktree in repository.worktrees {
        consider(id: worktree.id, directory: worktree.workingDirectory)
      }
    }
    return best?.id
  }
}

struct ActiveAgentWorktreeMetadata: Equatable {
  let repositoryNamesByWorktreeID: [Worktree.ID: String]
  let worktreeDirectoryNamesByWorktreeID: [Worktree.ID: String]
  let branchNamesByWorktreeID: [Worktree.ID: String]
  let repositoryColorsByWorktreeID: [Worktree.ID: RepositoryColorChoice]
}

struct ActiveAgentRowDisplay: Equatable {
  let titleName: String
  let branchName: String
  let color: RepositoryColorChoice?
}
