import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import Maestro

@MainActor
struct WindowTitleTests {
  @Test func formatIncludesTabWhenPresent() {
    #expect(WindowTitle.format(repository: "Maestro", tab: "codex") == "Maestro · codex")
  }

  @Test func formatDropsEmptyTab() {
    #expect(WindowTitle.format(repository: "Maestro", tab: nil) == "Maestro")
    #expect(WindowTitle.format(repository: "Maestro", tab: "") == "Maestro")
  }

  @Test func sanitizeRemovesControlCharacters() {
    #expect(WindowTitle.sanitize("codex\nsecret\u{1B}") == "codexsecret")
    #expect(WindowTitle.sanitize("\n\t\u{07}") == nil)
  }

  @Test func computeUsesAppTitleWithoutSelection() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    #expect(WindowTitle.compute(repositories: RepositoriesFeature.State(), terminalManager: manager) == "Maestro")
  }

  @Test func computeUsesViewTitlesForCanvasAndArchive() {
    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    var state = RepositoriesFeature.State()

    state.selection = .canvas
    #expect(WindowTitle.compute(repositories: state, terminalManager: manager) == "Canvas")

    state.selection = .archivedWorktrees
    #expect(WindowTitle.compute(repositories: state, terminalManager: manager) == "Archived Worktrees")
  }

  @Test func computeFallsBackToAppNameWhenWorktreeHasNoActiveTab() {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = makeWorktree(rootURL: rootURL)
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(worktree.id)

    let terminalState = WorktreeTerminalState(runtime: GhosttyRuntime(), worktree: worktree)
    let tabId = terminalState.tabManager.createTab(title: "codex", icon: nil)
    terminalState.tabManager.closeTab(tabId)

    #expect(
      WindowTitle.compute(
        repositories: state,
        terminalState: { id in id == worktree.id ? terminalState : nil }
      ) == "Maestro"
    )

    #expect(
      WindowTitle.compute(
        repositories: state,
        terminalState: { _ in nil }
      ) == "Maestro"
    )
  }

  @Test func computeUsesCustomRepositoryTitleAndSelectedTabTitle() {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let worktree = makeWorktree(rootURL: rootURL)
    let repository = Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: [worktree])
    )
    var state = RepositoriesFeature.State(repositories: [repository])
    state.selection = .worktree(worktree.id)
    state.repositoryCustomTitles[repository.id] = "Maestro"

    let terminalState = WorktreeTerminalState(runtime: GhosttyRuntime(), worktree: worktree)
    _ = terminalState.tabManager.createTab(title: "codex\nhidden", icon: nil)

    #expect(
      WindowTitle.compute(
        repositories: state,
        terminalState: { id in id == worktree.id ? terminalState : nil }
      ) == "Maestro · codexhidden"
    )
  }

  private func makeWorktree(rootURL: URL) -> Worktree {
    Worktree(
      id: rootURL.appendingPathComponent("main").path(percentEncoded: false),
      name: "main",
      detail: "detail",
      workingDirectory: rootURL.appendingPathComponent("main"),
      repositoryRootURL: rootURL
    )
  }
}
