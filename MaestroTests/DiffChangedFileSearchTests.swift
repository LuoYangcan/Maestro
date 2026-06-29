import Testing

@testable import Maestro

struct DiffChangedFileSearchTests {
  @Test func isfileconneMatchesPascalCaseBasenames() {
    let files = [
      changedFile("Maestro/Features/DiffView/DiffWindowContentView.swift"),
      changedFile("Maestro/Support/IsFileConnected.swift"),
      changedFile("Maestro/Support/IsFileConnectionClient.swift"),
    ]

    let result = DiffChangedFileSearch.rankedFiles(files, query: "isfileconne")

    #expect(result.map(\.displayName) == ["IsFileConnected.swift", "IsFileConnectionClient.swift"])
  }

  @Test func basenameMatchRanksAboveDirectoryPathMatch() {
    let basenameMatch = changedFile("Maestro/Support/SearchMatcher.swift")
    let pathMatch = changedFile("Maestro/Search/Utilities/FileList.swift")

    let result = DiffChangedFileSearch.rankedFiles([pathMatch, basenameMatch], query: "search")

    #expect(result.map(\.displayName) == ["SearchMatcher.swift", "FileList.swift"])
  }

  @Test func pathPiecesMatchAcrossDirectoryAndBasename() {
    let file = changedFile("Maestro/Features/DiffView/DiffWindowContentView.swift")

    let result = DiffChangedFileSearch.rankedFiles([file], query: "features diff")

    #expect(result == [file])
  }

  @Test func compressedCamelQueriesMatchBasename() {
    let file = changedFile("Maestro/Features/CommandPalette/Reducer/CommandPaletteFeature.swift")

    let cpfResult = DiffChangedFileSearch.rankedFiles([file], query: "cpf")
    let cmdpalfeatResult = DiffChangedFileSearch.rankedFiles([file], query: "cmdpalfeat")

    #expect(cpfResult == [file])
    #expect(cmdpalfeatResult == [file])
  }

  @Test func missingCharacterSubsequenceMatchesBasename() {
    let file = changedFile("Maestro/Support/SearchMatcher.swift")

    let result = DiffChangedFileSearch.rankedFiles([file], query: "serch")

    #expect(result == [file])
  }

  @Test func emptyAndWhitespaceQueryReturnOriginalOrder() {
    let files = [
      changedFile("A.swift"),
      changedFile("B.swift"),
      changedFile("C.swift"),
    ]

    #expect(DiffChangedFileSearch.rankedFiles(files, query: "") == files)
    #expect(DiffChangedFileSearch.rankedFiles(files, query: "   ") == files)
  }

  @Test func renamedFilesCanMatchOldAndNewPath() {
    let file = DiffChangedFile(
      status: .renamed,
      oldPath: "Maestro/Old/LegacyConnection.swift",
      newPath: "Maestro/New/FileConnection.swift"
    )

    #expect(DiffChangedFileSearch.rankedFiles([file], query: "legacyconnection") == [file])
    #expect(DiffChangedFileSearch.rankedFiles([file], query: "fileconnection") == [file])
  }

  @Test func deletedFilesCanMatchOldPath() {
    let file = DiffChangedFile(status: .deleted, oldPath: "Maestro/Removed/ObsoleteSearch.swift", newPath: nil)

    let result = DiffChangedFileSearch.rankedFiles([file], query: "obsoletesearch")

    #expect(result == [file])
  }

  @Test func statusTextCanSupplementFileMatching() {
    let deleted = DiffChangedFile(status: .deleted, oldPath: "Maestro/FileA.swift", newPath: nil)
    let added = DiffChangedFile(status: .added, oldPath: nil, newPath: "Maestro/FileB.swift")

    let result = DiffChangedFileSearch.rankedFiles([added, deleted], query: "deleted")

    #expect(result == [deleted])
  }

  @Test func noReasonableMatchReturnsEmptyList() {
    let files = [changedFile("Maestro/Support/SearchMatcher.swift")]

    let result = DiffChangedFileSearch.rankedFiles(files, query: "zzzzzz")

    #expect(result.isEmpty)
  }
}

private func changedFile(_ path: String) -> DiffChangedFile {
  DiffChangedFile(status: .modified, oldPath: path, newPath: path)
}
