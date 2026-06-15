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

  /// Three-tier resolution for the displayed name/branch of a single agent:
  /// 1. `workingDirectory` falls inside a known repo/worktree, so the label tracks live branch
  ///    renames through `metadata`. When that directory only resolves to an ancestor of the
  ///    owning worktree (e.g. the agent's cwd sits at the repo root above the tab's worktree),
  ///    the owning worktree is more specific and wins instead.
  /// 2. `workingDirectory` is known but outside every repo, so derive a name from its last path
  ///    component.
  /// 3. `workingDirectory` is unknown, so fall back to the surface's owning worktree.
  static func display(
    for entry: ActiveAgentEntry,
    repositories: IdentifiedArrayOf<Repository>,
    metadata: ActiveAgentWorktreeMetadata
  ) -> ActiveAgentRowDisplay {
    if let workingDirectory = entry.workingDirectory {
      if let key = resolveWorktreeID(forWorkingDirectory: workingDirectory, in: repositories) {
        let displayKey = displayWorktreeID(resolved: key, owning: entry.worktreeID, in: repositories)
        let fallbackName = workingDirectory.lastPathComponent
        return ActiveAgentRowDisplay(
          titleName: metadata.worktreeDirectoryNamesByWorktreeID[displayKey] ?? fallbackName,
          branchName: metadata.branchNamesByWorktreeID[displayKey] ?? fallbackName,
          color: metadata.repositoryColorsByWorktreeID[displayKey]
        )
      }
      let name = Repository.name(for: workingDirectory)
      return ActiveAgentRowDisplay(titleName: name, branchName: name, color: nil)
    }
    return ActiveAgentRowDisplay(
      titleName: metadata.worktreeDirectoryNamesByWorktreeID[entry.worktreeID] ?? entry.worktreeName,
      branchName: metadata.branchNamesByWorktreeID[entry.worktreeID] ?? entry.worktreeName,
      color: metadata.repositoryColorsByWorktreeID[entry.worktreeID]
    )
  }

  /// Picks which worktree id to display once the agent's cwd has resolved to `resolved`.
  /// Falls back to the `owning` worktree when `resolved` is only a strict ancestor of it, since
  /// the owning worktree (the tab's real worktree) is the more specific location. Keeps `resolved`
  /// when it is the owner itself, a deeper child, or an unrelated tree (the "agent cd'd into a
  /// different repo" case must not regress). When either directory can't be looked up there is no
  /// basis for the comparison, so `resolved` stays.
  private static func displayWorktreeID(
    resolved: Worktree.ID,
    owning: Worktree.ID,
    in repositories: IdentifiedArrayOf<Repository>
  ) -> Worktree.ID {
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
  /// must stay identical to `worktreeMetadata(...)` and `resolveWorktreeID(forWorkingDirectory:in:)`.
  /// Changing the key in any one of those three functions without updating the other two will
  /// silently desync them and produce incorrect ancestor comparisons or missing metadata lookups.
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
