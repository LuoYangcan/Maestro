import ComposableArchitecture
import Foundation
import Testing

@testable import Maestro

@MainActor
struct ActiveAgentsFeatureTests {
  // The child `ActiveAgentsFeature` only upserts entries in insertion order; the
  // repository → worktree → branch sort happens in the parent `RepositoriesFeature`
  // (it owns `state.repositories`, which the display names — and therefore the sort
  // keys — are resolved from). This verifies the child's insertion contract; the
  // parent's re-sort is covered by `RepositoriesFeatureTests` and the pure-comparator
  // tests below.
  @Test func childReducerUpsertsEntriesInInsertionOrder() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    let old = Date(timeIntervalSince1970: 10)
    let new = Date(timeIntervalSince1970: 20)
    let idle = entry(id: UUID(0), state: .idle, changedAt: new)
    let blocked = entry(id: UUID(1), state: .blocked, changedAt: old)
    let working = entry(id: UUID(2), state: .working, changedAt: new)
    let done = entry(id: UUID(3), state: .done, changedAt: new)
    let updatedIdle = entry(id: UUID(0), state: .blocked, changedAt: Date(timeIntervalSince1970: 30))

    await store.send(.agentEntryChanged(idle, autoShowPanel: false)) {
      $0.entries = [idle]
      $0.creationSeqBySurfaceID = [idle.surfaceID: 0]
      $0.nextCreationSeq = 1
    }
    await store.send(.agentEntryChanged(blocked, autoShowPanel: false)) {
      $0.entries = [idle, blocked]
      $0.creationSeqBySurfaceID = [idle.surfaceID: 0, blocked.surfaceID: 1]
      $0.nextCreationSeq = 2
    }
    await store.send(.agentEntryChanged(working, autoShowPanel: false)) {
      $0.entries = [idle, blocked, working]
      $0.creationSeqBySurfaceID = [idle.surfaceID: 0, blocked.surfaceID: 1, working.surfaceID: 2]
      $0.nextCreationSeq = 3
    }
    await store.send(.agentEntryChanged(done, autoShowPanel: false)) {
      $0.entries = [idle, blocked, working, done]
      $0.creationSeqBySurfaceID = [
        idle.surfaceID: 0, blocked.surfaceID: 1, working.surfaceID: 2, done.surfaceID: 3,
      ]
      $0.nextCreationSeq = 4
    }
    // Updating an existing entry replaces it in place — the child never reorders, and the
    // surface keeps its creation sequence (the counter does not advance on an upsert).
    await store.send(.agentEntryChanged(updatedIdle, autoShowPanel: false)) {
      $0.entries = [updatedIdle, blocked, working, done]
    }
  }

  // MARK: - Sort comparator (pure function)

  @Test func sortGroupsByRepositoryFirstAcrossRepositories() {
    // RepoB/xx and RepoA/yy inserted out of order — repository is the top key, so
    // every RepoA agent sorts ahead of every RepoB agent regardless of input order.
    let repoA = sortRepository(id: "/repos/a", name: "RepoA", worktrees: [("/repos/a/yy", "yy")])
    let repoB = sortRepository(id: "/repos/b", name: "RepoB", worktrees: [("/repos/b/xx", "xx")])
    let agentB = sortEntry(id: UUID(1), workingDirectory: "/repos/b/xx")
    let agentA = sortEntry(id: UUID(2), workingDirectory: "/repos/a/yy")

    let sorted = sortEntries([agentB, agentA], repositories: [repoB, repoA])

    #expect(sorted.map(\.id) == [agentA.id, agentB.id])
  }

  @Test func sortOrdersWorktreesWithinRepositoryByDisplayName() {
    let repo = sortRepository(
      id: "/repos/r",
      name: "Repo",
      worktrees: [
        ("/repos/r/zebra", "branch-z"),
        ("/repos/r/alpha", "branch-a"),
        ("/repos/r/mango", "branch-m"),
      ]
    )
    let zebra = sortEntry(id: UUID(1), workingDirectory: "/repos/r/zebra")
    let alpha = sortEntry(id: UUID(2), workingDirectory: "/repos/r/alpha")
    let mango = sortEntry(id: UUID(3), workingDirectory: "/repos/r/mango")

    let sorted = sortEntries([zebra, alpha, mango], repositories: [repo])

    #expect(sorted.map(\.id) == [alpha.id, mango.id, zebra.id])
  }

  @Test func sortUsesNaturalOrderForBranchNamesWithinSameWorktree() {
    // Same repository, two worktrees that both display as `alpha` (their directory's
    // last path component), differing only by branch `feat-2` / `feat-10`.
    // `localizedStandardCompare` puts `feat-2` first (numeric), unlike a lexicographic
    // `<` which would order `feat-10` before `feat-2`.
    let repo = sortRepository(
      id: "/repos/r",
      name: "Repo",
      worktrees: [
        ("/repos/r/ten/alpha", "feat-10"),
        ("/repos/r/two/alpha", "feat-2"),
      ]
    )
    let feat10 = sortEntry(id: UUID(1), workingDirectory: "/repos/r/ten/alpha")
    let feat2 = sortEntry(id: UUID(2), workingDirectory: "/repos/r/two/alpha")

    let sorted = sortEntries([feat10, feat2], repositories: [repo])

    #expect(sorted.map(\.id) == [feat2.id, feat10.id])
    // Guard against a lexicographic regression: `<` would order `feat-10` first.
    #expect(sorted.map(\.id) != [feat10.id, feat2.id])
  }

  @Test func sortOrderIsUnaffectedByDisplayStateChange() {
    let repo = sortRepository(
      id: "/repos/r",
      name: "Repo",
      worktrees: [
        ("/repos/r/alpha", "branch-a"),
        ("/repos/r/zebra", "branch-z"),
      ]
    )
    let alphaWorking = sortEntry(id: UUID(1), workingDirectory: "/repos/r/alpha", state: .working)
    let zebra = sortEntry(id: UUID(2), workingDirectory: "/repos/r/zebra", state: .idle)
    let baseline = sortEntries([alphaWorking, zebra], repositories: [repo])
    #expect(baseline.map(\.id) == [alphaWorking.id, zebra.id])

    // Re-sorting after an in-place displayState change yields the same order: the
    // sort keys are display names, not state.
    let alphaBlocked = sortEntry(id: UUID(1), workingDirectory: "/repos/r/alpha", state: .blocked)
    let afterChange = sortEntries([alphaBlocked, zebra], repositories: [repo])
    #expect(afterChange.map(\.id) == [alphaWorking.id, zebra.id])
  }

  @Test func sortIsDeterministicForEqualDisplayKeys() {
    // Multiple agents in the same repository + worktree + branch (different surfaces):
    // no business tie-break, but reversing the input must produce an identical result
    // (the surfaceID stability guard prevents flicker).
    let repo = sortRepository(id: "/repos/r", name: "Repo", worktrees: [("/repos/r/alpha", "main")])
    let first = sortEntry(id: UUID(1), workingDirectory: "/repos/r/alpha")
    let second = sortEntry(id: UUID(2), workingDirectory: "/repos/r/alpha")
    let third = sortEntry(id: UUID(3), workingDirectory: "/repos/r/alpha")

    let forward = sortEntries([first, second, third], repositories: [repo])
    let reversed = sortEntries([third, second, first], repositories: [repo])

    #expect(forward.map(\.id) == reversed.map(\.id))
  }

  @Test func sortIsNoOpForEmptyAndSingleEntry() {
    let empty: IdentifiedArrayOf<ActiveAgentEntry> = []
    #expect(sortEntries(empty, repositories: []).isEmpty)

    let single = sortEntry(id: UUID(1), workingDirectory: "/repos/r/alpha")
    let sorted = sortEntries([single], repositories: [])
    #expect(sorted.map(\.id) == [single.id])
  }

  @Test func sortFallsBackForEntriesOutsideEveryRepository() {
    // One agent runs inside a known repository; another runs in a directory that falls
    // outside every repository. The outside entry's repository key is empty, so it sorts
    // ahead, and both order deterministically without crashing.
    let repo = sortRepository(id: "/repos/r", name: "Repo", worktrees: [("/repos/r/alpha", "main")])
    let inside = sortEntry(id: UUID(1), workingDirectory: "/repos/r/alpha")
    let outside = sortEntry(id: UUID(2), workingDirectory: "/elsewhere/loose")

    let forward = sortEntries([inside, outside], repositories: [repo])
    let reversed = sortEntries([outside, inside], repositories: [repo])

    #expect(forward.map(\.id) == [outside.id, inside.id])
    #expect(forward.map(\.id) == reversed.map(\.id))
  }

  // MARK: - Creation-order tier (AMD-1)

  @Test func sortOrdersEqualDisplayGroupByCreationSequence() {
    // Three agents in the same repository + worktree + branch differ only by their
    // creation sequence. The smaller sequence (created earlier) sorts first, and a
    // reversed input produces the same order.
    let repo = sortRepository(id: "/repos/r", name: "Repo", worktrees: [("/repos/r/alpha", "main")])
    let first = sortEntry(id: UUID(1), workingDirectory: "/repos/r/alpha")
    let second = sortEntry(id: UUID(2), workingDirectory: "/repos/r/alpha")
    let third = sortEntry(id: UUID(3), workingDirectory: "/repos/r/alpha")
    let creationSeq: [UUID: Int] = [first.surfaceID: 0, second.surfaceID: 1, third.surfaceID: 2]

    let forward = sortEntries([first, second, third], repositories: [repo], creationSeqBySurfaceID: creationSeq)
    let reversed = sortEntries([third, second, first], repositories: [repo], creationSeqBySurfaceID: creationSeq)

    #expect(forward.map(\.id) == [first.id, second.id, third.id])
    #expect(forward.map(\.id) == reversed.map(\.id))
  }

  @Test func creationSequenceNeverOverridesDisplayGrouping() {
    // The earlier-created agent lives in the later-sorting worktree (`zebra`). Creation
    // sequence is the lowest tier, so worktree grouping still wins: `alpha` precedes
    // `zebra` even though `zebra`'s agent was created first.
    let repo = sortRepository(
      id: "/repos/r",
      name: "Repo",
      worktrees: [
        ("/repos/r/zebra", "z"),
        ("/repos/r/alpha", "a"),
      ]
    )
    let zebra = sortEntry(id: UUID(1), workingDirectory: "/repos/r/zebra")
    let alpha = sortEntry(id: UUID(2), workingDirectory: "/repos/r/alpha")
    // zebra created first (seq 0), alpha second (seq 1) — yet grouping puts alpha ahead.
    let creationSeq: [UUID: Int] = [zebra.surfaceID: 0, alpha.surfaceID: 1]

    let sorted = sortEntries([zebra, alpha], repositories: [repo], creationSeqBySurfaceID: creationSeq)

    #expect(sorted.map(\.id) == [alpha.id, zebra.id])
  }

  // MARK: - Creation-sequence tracking (reducer assign / cleanup)

  @Test func agentEntryChangedAssignsCreationSequenceOnFirstAppearance() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }
    let agentA = entry(id: UUID(0), state: .working, changedAt: Date(timeIntervalSince1970: 10))
    let agentB = entry(id: UUID(1), state: .idle, changedAt: Date(timeIntervalSince1970: 20))

    await store.send(.agentEntryChanged(agentA, autoShowPanel: false)) {
      $0.entries = [agentA]
      $0.creationSeqBySurfaceID = [agentA.surfaceID: 0]
      $0.nextCreationSeq = 1
    }
    await store.send(.agentEntryChanged(agentB, autoShowPanel: false)) {
      $0.entries = [agentA, agentB]
      $0.creationSeqBySurfaceID = [agentA.surfaceID: 0, agentB.surfaceID: 1]
      $0.nextCreationSeq = 2
    }
  }

  @Test func agentEntryChangedKeepsCreationSequenceOnUpsert() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }
    let agent = entry(id: UUID(0), state: .working, changedAt: Date(timeIntervalSince1970: 10))
    let updated = entry(id: UUID(0), state: .blocked, changedAt: Date(timeIntervalSince1970: 30))

    await store.send(.agentEntryChanged(agent, autoShowPanel: false)) {
      $0.entries = [agent]
      $0.creationSeqBySurfaceID = [agent.surfaceID: 0]
      $0.nextCreationSeq = 1
    }
    // Re-sending the same surface (a displayState update) keeps its sequence and does not
    // bump the counter.
    await store.send(.agentEntryChanged(updated, autoShowPanel: false)) {
      $0.entries = [updated]
    }
  }

  @Test func agentEntryRemovedClearsSequenceWithoutRewindingCounter() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }
    let agentA = entry(id: UUID(0), state: .working, changedAt: Date(timeIntervalSince1970: 10))
    let agentB = entry(id: UUID(1), state: .idle, changedAt: Date(timeIntervalSince1970: 20))
    let agentC = entry(id: UUID(2), state: .blocked, changedAt: Date(timeIntervalSince1970: 30))

    await store.send(.agentEntryChanged(agentA, autoShowPanel: false)) {
      $0.entries = [agentA]
      $0.creationSeqBySurfaceID = [agentA.surfaceID: 0]
      $0.nextCreationSeq = 1
    }
    await store.send(.agentEntryChanged(agentB, autoShowPanel: false)) {
      $0.entries = [agentA, agentB]
      $0.creationSeqBySurfaceID = [agentA.surfaceID: 0, agentB.surfaceID: 1]
      $0.nextCreationSeq = 2
    }
    await store.send(.agentEntryChanged(agentC, autoShowPanel: false)) {
      $0.entries = [agentA, agentB, agentC]
      $0.creationSeqBySurfaceID = [agentA.surfaceID: 0, agentB.surfaceID: 1, agentC.surfaceID: 2]
      $0.nextCreationSeq = 3
    }
    // Removing B clears only its sequence; the counter is not rewound, so A (0) and C (2)
    // keep their relative order.
    await store.send(.agentEntryRemoved(agentB.id)) {
      $0.entries = [agentA, agentC]
      $0.creationSeqBySurfaceID = [agentA.surfaceID: 0, agentC.surfaceID: 2]
    }
  }

  // MARK: - Keyboard navigation regression (follows visible = stored order)

  @Test func keyboardNavigationFollowsSortedStorageOrder() {
    // Build entries in scrambled insertion order, sort them, then drive keyboard
    // navigation: `entryID` steps through `state.entries` storage order, which must
    // equal the visible (sorted) order. This guards against sorting only in the view
    // layer while navigation walks an unsorted array.
    let repo = sortRepository(
      id: "/repos/r",
      name: "Repo",
      worktrees: [
        ("/repos/r/zebra", "z"),
        ("/repos/r/alpha", "a"),
        ("/repos/r/mango", "m"),
      ]
    )
    let zebra = sortEntry(id: UUID(1), workingDirectory: "/repos/r/zebra")
    let alpha = sortEntry(id: UUID(2), workingDirectory: "/repos/r/alpha")
    let mango = sortEntry(id: UUID(3), workingDirectory: "/repos/r/mango")
    let sorted = sortEntries([zebra, alpha, mango], repositories: [repo])
    // Visible order is alpha → mango → zebra.
    #expect(sorted.map(\.id) == [alpha.id, mango.id, zebra.id])

    // `.next` from no anchor starts at the first visible entry and wraps around.
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .next, in: sorted) == alpha.id)
    #expect(
      ActiveAgentsFeature.entryID(navigatingFrom: alpha.surfaceID, direction: .next, in: sorted) == mango.id
    )
    #expect(
      ActiveAgentsFeature.entryID(navigatingFrom: mango.surfaceID, direction: .next, in: sorted) == zebra.id
    )
    #expect(
      ActiveAgentsFeature.entryID(navigatingFrom: zebra.surfaceID, direction: .next, in: sorted) == alpha.id
    )
    // `.previous` walks the same visible order backwards with wrap-around.
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .previous, in: sorted) == zebra.id)
    #expect(
      ActiveAgentsFeature.entryID(navigatingFrom: alpha.surfaceID, direction: .previous, in: sorted) == zebra.id
    )
  }

  @Test func autoShowRevealsHiddenPanelOnAgentEntry() async {
    let state = ActiveAgentsFeature.State()
    state.$isPanelHidden.withLock { $0 = true }
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }
    let agent = entry(id: UUID(0), state: .working, changedAt: Date(timeIntervalSince1970: 10))

    await store.send(.agentEntryChanged(agent, autoShowPanel: true)) {
      $0.entries = [agent]
      $0.creationSeqBySurfaceID = [agent.surfaceID: 0]
      $0.nextCreationSeq = 1
      $0.$isPanelHidden.withLock { $0 = false }
    }
  }

  @Test func panelHeightIsClamped() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    await store.send(.panelHeightChanged(20)) {
      $0.$panelHeight.withLock { $0 = 120 }
    }
    await store.send(.panelHeightChanged(900)) {
      $0.$panelHeight.withLock { $0 = 560 }
    }
  }

  @Test func maximumPanelHeightKeepsRepositoryListVisible() {
    #expect(ActiveAgentsFeature.maximumPanelHeight(forContainerHeight: 900) == 560)
    #expect(ActiveAgentsFeature.maximumPanelHeight(forContainerHeight: 500) == 300)
    #expect(ActiveAgentsFeature.maximumPanelHeight(forContainerHeight: 250) == 120)
  }

  @Test func navigationReturnsNilForEmptyList() {
    let entries: IdentifiedArrayOf<ActiveAgentEntry> = []
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .next, in: entries) == nil)
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .previous, in: entries) == nil)
  }

  @Test func navigationWithoutAnchorStartsFromEdges() {
    let entries = sampleEntries()
    // No focus, or focus on a surface that is not in the list, anchors on an edge.
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .next, in: entries) == UUID(0))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: nil, direction: .previous, in: entries) == UUID(2))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(99), direction: .next, in: entries) == UUID(0))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(99), direction: .previous, in: entries) == UUID(2))
  }

  @Test func navigationStepsAndWrapsAroundAnchor() {
    let entries = sampleEntries()
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(0), direction: .next, in: entries) == UUID(1))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(2), direction: .next, in: entries) == UUID(0))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(1), direction: .previous, in: entries) == UUID(0))
    #expect(ActiveAgentsFeature.entryID(navigatingFrom: UUID(0), direction: .previous, in: entries) == UUID(2))
  }

  @Test func selectNextEntryAdvancesAnchorAndTapsNeighbour() async {
    var state = ActiveAgentsFeature.State()
    state.entries = sampleEntries()
    state.focusedSurfaceID = UUID(0)
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }

    await store.send(.selectNextEntry) {
      $0.focusedSurfaceID = UUID(1)
    }
    await store.receive(.entryTapped(UUID(1)))
  }

  @Test func selectPreviousEntryWrapsToLastWhenAtFirst() async {
    var state = ActiveAgentsFeature.State()
    state.entries = sampleEntries()
    state.focusedSurfaceID = UUID(0)
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }

    await store.send(.selectPreviousEntry) {
      $0.focusedSurfaceID = UUID(2)
    }
    await store.receive(.entryTapped(UUID(2)))
  }

  @Test func navigationWithoutEntriesIsNoOp() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    await store.send(.selectNextEntry)
    await store.send(.selectPreviousEntry)
  }

  @Test func entryTappedUpdatesFocusAnchor() async {
    var state = ActiveAgentsFeature.State()
    state.entries = sampleEntries()
    let store = TestStore(initialState: state) {
      ActiveAgentsFeature()
    }

    // Tapping mirrors the entry's surface into the focus anchor so keyboard
    // navigation continues from the just-selected agent, without relying on the
    // (per-worktree deduplicated) async `focusChanged` event.
    await store.send(.entryTapped(UUID(2))) {
      $0.focusedSurfaceID = UUID(2)
    }
  }

  @Test func focusedSurfaceChangedUpdatesAnchor() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    await store.send(.focusedSurfaceChanged(UUID(7))) {
      $0.focusedSurfaceID = UUID(7)
    }
    await store.send(.focusedSurfaceChanged(nil)) {
      $0.focusedSurfaceID = nil
    }
  }

  private func sampleEntries() -> IdentifiedArrayOf<ActiveAgentEntry> {
    let now = Date(timeIntervalSince1970: 10)
    return [
      entry(id: UUID(0), state: .working, changedAt: now),
      entry(id: UUID(1), state: .idle, changedAt: now),
      entry(id: UUID(2), state: .blocked, changedAt: now),
    ]
  }

  private func entry(id: UUID, state: AgentDisplayState, changedAt: Date) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: id,
      worktreeID: "/repo/wt",
      worktreeName: "wt",
      workingDirectory: nil,
      tabID: TerminalTabID(rawValue: UUID()),
      tabTitle: "1",
      surfaceID: id,
      paneIndex: 1,
      agent: .codex,
      rawState: state == .blocked ? .blocked : state == .working ? .working : .idle,
      displayState: state,
      lastChangedAt: changedAt
    )
  }

  // MARK: - Sort-test fixtures

  /// Builds a repository whose worktrees carry an explicit displayed worktree name and
  /// branch: `dir`'s last path component is the displayed worktree title, and `branch`
  /// becomes `Worktree.name` (the displayed branch). Agents resolve to a worktree when
  /// their `workingDirectory` falls inside `dir`.
  private func sortRepository(
    id: String,
    name: String,
    worktrees: [(dir: String, branch: String)]
  ) -> Repository {
    let worktreeModels = worktrees.map { worktree in
      Worktree(
        id: worktree.dir,
        name: worktree.branch,
        detail: "detail",
        workingDirectory: URL(fileURLWithPath: worktree.dir),
        repositoryRootURL: URL(fileURLWithPath: id)
      )
    }
    return Repository(
      id: id,
      rootURL: URL(fileURLWithPath: id),
      name: name,
      kind: .git,
      worktrees: IdentifiedArray(uniqueElements: worktreeModels)
    )
  }

  /// An agent whose displayed repository/worktree/branch are resolved from
  /// `workingDirectory` (matching how rows render), so the sort keys exercise the real
  /// `ActiveAgentRowDisplayResolver` path.
  private func sortEntry(
    id: UUID,
    workingDirectory: String,
    state: AgentDisplayState = .working
  ) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: id,
      worktreeID: "owner-\(id.uuidString)",
      worktreeName: "owner",
      workingDirectory: URL(fileURLWithPath: workingDirectory),
      tabID: TerminalTabID(rawValue: UUID()),
      tabTitle: "1",
      surfaceID: id,
      paneIndex: 1,
      agent: .codex,
      rawState: state == .blocked ? .blocked : state == .working ? .working : .idle,
      displayState: state,
      lastChangedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private func sortEntries(
    _ entries: IdentifiedArrayOf<ActiveAgentEntry>,
    repositories: [Repository],
    creationSeqBySurfaceID: [UUID: Int] = [:]
  ) -> IdentifiedArrayOf<ActiveAgentEntry> {
    let repositoryArray = IdentifiedArray(uniqueElements: repositories)
    let metadata = ActiveAgentRowDisplayResolver.worktreeMetadata(
      repositories: repositoryArray,
      customTitles: [:]
    )
    return ActiveAgentEntrySorter.sorted(
      entries: entries,
      repositories: repositoryArray,
      metadata: metadata,
      creationSeqBySurfaceID: creationSeqBySurfaceID
    )
  }
}

extension UUID {
  fileprivate init(_ value: UInt8) {
    self.init(uuid: (value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  }
}
