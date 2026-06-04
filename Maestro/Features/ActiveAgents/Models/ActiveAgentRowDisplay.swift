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
  ///    renames through `metadata`.
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
        let fallbackName = workingDirectory.lastPathComponent
        return ActiveAgentRowDisplay(
          titleName: metadata.worktreeDirectoryNamesByWorktreeID[key] ?? fallbackName,
          branchName: metadata.branchNamesByWorktreeID[key] ?? fallbackName,
          color: metadata.repositoryColorsByWorktreeID[key]
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
