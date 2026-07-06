import Testing

@testable import Maestro

struct DiffWindowStateTests {
  @MainActor
  @Test func emptyQueryShowsAllFiles() {
    let files = [changedFile("Maestro/Support/SearchMatcher.swift"), changedFile("Maestro/FileList.swift")]
    let state = DiffWindowState()
    state.changedFiles = files
    state.searchResults = [match(file: files[0], query: "search")]

    #expect(state.sidebarContent == .allFiles(files))
  }

  @MainActor
  @Test func contentMatchesTakePriorityOverFileMatches() {
    let files = [changedFile("Maestro/Support/SearchMatcher.swift")]
    let matches = [match(file: files[0], query: "search")]
    let state = DiffWindowState()
    state.changedFiles = files
    state.searchQuery = "search"
    state.searchResults = matches

    #expect(state.sidebarContent == .contentMatches(matches))
  }

  @MainActor
  @Test func contentMissFallsBackToRankedFileMatches() {
    let files = [
      changedFile("Maestro/Search/Utilities/FileList.swift"),
      changedFile("Maestro/Support/SearchMatcher.swift"),
    ]
    let state = DiffWindowState()
    state.changedFiles = files
    state.searchQuery = "search"

    let expectedFiles = DiffChangedFileSearch.rankedFiles(files, query: "search")

    #expect(state.sidebarContent == .filteredFiles(expectedFiles))
  }

  @MainActor
  @Test func contentAndFileMissShowsNoResults() {
    let state = DiffWindowState()
    state.changedFiles = [changedFile("Maestro/Support/SearchMatcher.swift")]
    state.searchQuery = "zzzzzz"

    #expect(state.sidebarContent == .noResults)
  }

  @MainActor
  @Test func activeQueryWhileLoadingKeepsContentSearchLoadingState() {
    let state = DiffWindowState()
    state.isLoadingFiles = true
    state.searchQuery = "search"

    #expect(state.sidebarContent == .contentMatches([]))
  }
}

private func changedFile(_ path: String) -> DiffChangedFile {
  DiffChangedFile(status: .modified, oldPath: path, newPath: path)
}

private func match(file: DiffChangedFile, query: String) -> DiffSearchMatch {
  DiffSearchMatch(
    id: "\(file.id)#new#1#0",
    fileID: file.id,
    fileDisplayName: file.displayName,
    side: .new,
    lineNumber: 1,
    lineText: "let \(query) = true"
  )
}
