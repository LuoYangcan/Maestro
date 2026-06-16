import Dependencies
import Foundation
import IdentifiedCollections
import Testing

@testable import Maestro

@Suite struct ActiveAgentRowDisplayResolverTests {
  // MARK: - Golden path

  // Old agent process whose cwd sits at the repository root (an ancestor of the tab's owning
  // worktree). `resolveWorktreeID` matches the repo-root worktree, but the owning worktree is the
  // more specific location, so the row must display the owning worktree, not the repo root.
  @Test func ancestorWorkingDirectoryFallsBackToOwningWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "memories-page-split",
      workingDirectory: repositoryRoot
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "memories-page-split")
    #expect(display.branchName == "memories-page-split")
  }

  // New agent whose cwd really lives inside its owning worktree (or a deeper child of it) — the
  // resolved worktree is exactly the owner, so the row keeps showing it. The fallback must not
  // misfire here.
  @Test func workingDirectoryInsideOwningWorktreeShowsOwningWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "memories-page-split",
      workingDirectory: childWorktreeDirectory.appending(path: "Sources/Feature")
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "memories-page-split")
    #expect(display.branchName == "memories-page-split")
  }

  // Regression baseline: agent cwd in an unrelated repo must display that repo, not fall back to
  // the owning worktree.
  @Test func workingDirectoryInUnrelatedRepoShowsThatRepo() {
    let repositories = repositoriesWithTwoRepos()
    let entry = entry(
      owningWorktreeID: repoAWorktreeID,
      owningWorktreeName: "repo-a-feature",
      workingDirectory: repoBWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == repoBWorktreeDirectory.lastPathComponent)
    #expect(display.branchName == "repo-b-feature")
  }

  // Agent cwd sits in a sibling worktree of the same repository (neither is an ancestor of the
  // other). Same repo → the row tracks the tab's owning worktree, not the sibling the agent cd'd to.
  @Test func workingDirectoryInSiblingWorktreeShowsOwningWorktree() {
    let repositories = repositoriesWithTwoSiblingWorktrees()
    let entry = entry(
      owningWorktreeID: siblingWorktreeAID,
      owningWorktreeName: "feat-a",
      workingDirectory: siblingWorktreeBDirectory
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "feat-a")
    #expect(display.branchName == "feat-a")
  }

  // Live repro: the tab owns the repo-root worktree (`main`), but the agent process cd'd into a
  // nested `.worktrees/...` descendant of the same repo. Same repo → the row must show the owning
  // (repo-root) worktree, not the nested descendant.
  @Test func workingDirectoryInDescendantWorktreeShowsOwningWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: "main-worktree",
      owningWorktreeName: "main",
      workingDirectory: childWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == repositoryRoot.lastPathComponent)
    #expect(display.branchName == "main")
  }

  // MARK: - Boundary

  // `workingDirectory == nil` → tier 3 fallback to the owning worktree's metadata, unchanged.
  @Test func nilWorkingDirectoryFallsBackToOwningWorktreeMetadata() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "stale-name",
      workingDirectory: nil
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "memories-page-split")
    #expect(display.branchName == "memories-page-split")
  }

  // cwd equals the owning worktree's own directory (not deeper, not an ancestor) → shows owning.
  @Test func workingDirectoryEqualToOwningWorktreeShowsOwningWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "memories-page-split",
      workingDirectory: childWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "memories-page-split")
    #expect(display.branchName == "memories-page-split")
  }

  // cwd outside every known repo/worktree (tier 2). A directory that belongs to no repository is
  // *not* "a different repository", so the row falls back to the tab's owning worktree rather than
  // deriving a meaningless folder name. (Intentional behavior change: previously showed "Downloads".)
  @Test func workingDirectoryOutsideAllReposShowsOwningWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let outside = URL(fileURLWithPath: "/Users/someone/Downloads")
    let entry = entry(
      owningWorktreeID: childWorktreeID,
      owningWorktreeName: "memories-page-split",
      workingDirectory: outside
    )

    let display = display(for: entry, repositories: repositories)

    #expect(display.titleName == "memories-page-split")
    #expect(display.branchName == "memories-page-split")
  }

  // Owning worktree id cannot be found in `repositories` (deleted/not loaded). With no basis for
  // the ancestor comparison, the resolved worktree is kept; must not crash.
  @Test func owningWorktreeNotFoundKeepsResolvedWorktree() {
    let repositories = repositoriesWithMainAndChildWorktree()
    // cwd resolves to the repo root; owner id is unknown, so the ancestor check can't run.
    let entry = entry(
      owningWorktreeID: "non-existent-worktree-id",
      owningWorktreeName: "ghost",
      workingDirectory: repositoryRoot
    )

    let display = display(for: entry, repositories: repositories)

    // No fallback basis → the resolved (repo-root) worktree's metadata is shown.
    #expect(display.titleName == repositoryRoot.lastPathComponent)
    #expect(display.branchName == "main")
  }

  // Plain-folder repo (keyed by repository id, directory == repo root) as the owning target: the
  // ancestor check still works when the owner is a plain folder. Here a git worktree at the root
  // would shadow it, so we model the plain folder as the deeper, more-specific owner inside an
  // outer git worktree that resolves as an ancestor.
  @Test func plainFolderOwnerFallsBackWhenResolvedIsAncestor() {
    let outerWorktreeDir = URL(fileURLWithPath: "/work/outer")
    let plainFolderDir = outerWorktreeDir.appending(path: "nested-folder")

    let gitRepo = Repository(
      id: "git-outer",
      rootURL: outerWorktreeDir,
      name: "outer",
      kind: .git,
      worktrees: [
        Worktree(
          id: "outer-wt",
          name: "outer-main",
          detail: "detail",
          workingDirectory: outerWorktreeDir,
          repositoryRootURL: outerWorktreeDir
        )
      ]
    )
    let plainRepo = Repository(
      id: "plain-folder",
      rootURL: plainFolderDir,
      name: "Nested Folder",
      kind: .plain,
      worktrees: []
    )
    let repositories = IdentifiedArray(uniqueElements: [gitRepo, plainRepo])

    // Agent cwd sits at the outer worktree (ancestor of the plain folder it actually owns).
    let entry = entry(
      owningWorktreeID: "plain-folder",
      owningWorktreeName: "Nested Folder",
      workingDirectory: outerWorktreeDir
    )

    let display = display(for: entry, repositories: repositories)

    // Resolved = outer worktree (ancestor) → falls back to the plain-folder owner.
    #expect(display.titleName == "nested-folder")
    #expect(display.branchName == "Nested Folder")
  }

  // MARK: - Sorter / display consistency

  // The sort key must read from the same worktree the row label shows. In the descendant layout the
  // label shows the owning (repo-root) worktree, so the sort key's worktree/branch must too — they
  // can no longer diverge into different ordering groups.
  @Test func sortKeyMatchesDisplayInDescendantLayout() {
    let repositories = repositoriesWithMainAndChildWorktree()
    let entry = entry(
      owningWorktreeID: "main-worktree",
      owningWorktreeName: "main",
      workingDirectory: childWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)
    let sortKey = sortKey(for: entry, repositories: repositories)

    #expect(sortKey.worktreeName == display.titleName)
    #expect(sortKey.branchName == display.branchName)
  }

  // Cross-repo: the agent really moved into a different repository, so both the label and the sort
  // key use the resolved worktree (repo-b) — still consistent with each other.
  @Test func sortKeyMatchesDisplayInCrossRepoLayout() {
    let repositories = repositoriesWithTwoRepos()
    let entry = entry(
      owningWorktreeID: repoAWorktreeID,
      owningWorktreeName: "repo-a-feature",
      workingDirectory: repoBWorktreeDirectory
    )

    let display = display(for: entry, repositories: repositories)
    let sortKey = sortKey(for: entry, repositories: repositories)

    #expect(sortKey.worktreeName == display.titleName)
    #expect(sortKey.branchName == display.branchName)
  }

  // MARK: - Fixtures

  private let repositoryRoot = URL(fileURLWithPath: "/work/today-platform-ios")
  private let childWorktreeID = "memories-page-split"
  private var childWorktreeDirectory: URL {
    repositoryRoot.appending(path: ".worktrees/memories-page-split")
  }

  /// A single git repo whose main worktree is the repo root and whose child worktree lives under
  /// `.worktrees/`. The repo-root worktree is therefore a strict ancestor of the child.
  private func repositoriesWithMainAndChildWorktree() -> IdentifiedArrayOf<Repository> {
    let repository = Repository(
      id: "today-platform-ios",
      rootURL: repositoryRoot,
      name: "today-platform-ios",
      kind: .git,
      worktrees: [
        Worktree(
          id: "main-worktree",
          name: "main",
          detail: "detail",
          workingDirectory: repositoryRoot,
          repositoryRootURL: repositoryRoot
        ),
        Worktree(
          id: childWorktreeID,
          name: "memories-page-split",
          detail: "detail",
          workingDirectory: childWorktreeDirectory,
          repositoryRootURL: repositoryRoot
        ),
      ]
    )
    return IdentifiedArray(uniqueElements: [repository])
  }

  private let siblingWorktreeAID = "feat-a-id"
  private let siblingWorktreeBID = "feat-b-id"
  private var siblingWorktreeADirectory: URL {
    URL(fileURLWithPath: "/work/repo/.worktrees/feat-a")
  }
  private var siblingWorktreeBDirectory: URL {
    URL(fileURLWithPath: "/work/repo/.worktrees/feat-b")
  }

  /// A single git repo with two parallel `.worktrees/` siblings. Neither directory contains the
  /// other, so the same-repo rule (not an ancestor check) is what makes the owning worktree win.
  private func repositoriesWithTwoSiblingWorktrees() -> IdentifiedArrayOf<Repository> {
    let repository = Repository(
      id: "repo",
      rootURL: URL(fileURLWithPath: "/work/repo"),
      name: "repo",
      kind: .git,
      worktrees: [
        Worktree(
          id: siblingWorktreeAID,
          name: "feat-a",
          detail: "detail",
          workingDirectory: siblingWorktreeADirectory,
          repositoryRootURL: URL(fileURLWithPath: "/work/repo")
        ),
        Worktree(
          id: siblingWorktreeBID,
          name: "feat-b",
          detail: "detail",
          workingDirectory: siblingWorktreeBDirectory,
          repositoryRootURL: URL(fileURLWithPath: "/work/repo")
        ),
      ]
    )
    return IdentifiedArray(uniqueElements: [repository])
  }

  private let repoAWorktreeID = "repo-a-feature"
  private var repoAWorktreeDirectory: URL {
    URL(fileURLWithPath: "/work/repo-a/.worktrees/feature")
  }
  private var repoBWorktreeDirectory: URL {
    URL(fileURLWithPath: "/work/repo-b/.worktrees/feature")
  }

  /// Two unrelated git repos, each with a worktree. Neither directory tree is an ancestor of the
  /// other.
  private func repositoriesWithTwoRepos() -> IdentifiedArrayOf<Repository> {
    let repoA = Repository(
      id: "repo-a",
      rootURL: URL(fileURLWithPath: "/work/repo-a"),
      name: "repo-a",
      kind: .git,
      worktrees: [
        Worktree(
          id: repoAWorktreeID,
          name: "repo-a-feature",
          detail: "detail",
          workingDirectory: repoAWorktreeDirectory,
          repositoryRootURL: URL(fileURLWithPath: "/work/repo-a")
        )
      ]
    )
    let repoB = Repository(
      id: "repo-b",
      rootURL: URL(fileURLWithPath: "/work/repo-b"),
      name: "repo-b",
      kind: .git,
      worktrees: [
        Worktree(
          id: "repo-b-feature-id",
          name: "repo-b-feature",
          detail: "detail",
          workingDirectory: repoBWorktreeDirectory,
          repositoryRootURL: URL(fileURLWithPath: "/work/repo-b")
        )
      ]
    )
    return IdentifiedArray(uniqueElements: [repoA, repoB])
  }

  private func entry(
    owningWorktreeID: Worktree.ID,
    owningWorktreeName: String,
    workingDirectory: URL?
  ) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: UUID(0),
      worktreeID: owningWorktreeID,
      worktreeName: owningWorktreeName,
      workingDirectory: workingDirectory,
      tabID: TerminalTabID(rawValue: UUID()),
      tabTitle: "1",
      surfaceID: UUID(0),
      paneIndex: 1,
      agent: .codex,
      rawState: .working,
      displayState: .working,
      lastChangedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private func display(
    for entry: ActiveAgentEntry,
    repositories: IdentifiedArrayOf<Repository>
  ) -> ActiveAgentRowDisplay {
    let metadata = ActiveAgentRowDisplayResolver.worktreeMetadata(
      repositories: repositories,
      customTitles: [:]
    )
    return ActiveAgentRowDisplayResolver.display(
      for: entry,
      repositories: repositories,
      metadata: metadata
    )
  }

  private func sortKey(
    for entry: ActiveAgentEntry,
    repositories: IdentifiedArrayOf<Repository>
  ) -> ActiveAgentEntrySorter.SortKey {
    let metadata = ActiveAgentRowDisplayResolver.worktreeMetadata(
      repositories: repositories,
      customTitles: [:]
    )
    return ActiveAgentEntrySorter.sortKey(
      for: entry,
      repositories: repositories,
      metadata: metadata,
      creationSeqBySurfaceID: [:]
    )
  }
}
