import Foundation
import Testing

@testable import Maestro

struct DiffSearchEngineTests {
  private func file(
    _ id: String,
    old: String = "",
    new: String = ""
  ) -> DiffSearchableFile {
    DiffSearchableFile(fileID: id, displayName: id, oldContents: old, newContents: new)
  }

  @Test func emptyQueryReturnsNoResults() {
    let files = [file("a.swift", new: "let foo = 1\nlet bar = 2")]
    #expect(DiffSearchEngine.search(query: "", in: files).isEmpty)
  }

  @Test func whitespaceOnlyQueryReturnsNoResults() {
    let files = [file("a.swift", new: "let foo = 1")]
    #expect(DiffSearchEngine.search(query: "   ", in: files).isEmpty)
  }

  @Test func noMatchReturnsNoResults() {
    let files = [file("a.swift", new: "let foo = 1\nlet bar = 2")]
    #expect(DiffSearchEngine.search(query: "qux", in: files).isEmpty)
  }

  @Test func multiFileMatchKeepsInputOrder() {
    let files = [
      file("first.swift", new: "needle here"),
      file("second.swift", new: "another needle"),
    ]
    let results = DiffSearchEngine.search(query: "needle", in: files)
    #expect(results.count == 2)
    #expect(results[0].fileID == "first.swift")
    #expect(results[1].fileID == "second.swift")
  }

  @Test func singleFileMultipleLinesEachProduceMatch() {
    let contents = "needle one\nno match\nneedle two\nneedle three"
    let results = DiffSearchEngine.search(query: "needle", in: [file("a.swift", new: contents)])
    #expect(results.count == 3)
    #expect(results.map(\.lineNumber) == [1, 3, 4])
  }

  @Test func matchIsCaseInsensitive() {
    let contents = "let foo = 1\nlet FOO = 2"
    let results = DiffSearchEngine.search(query: "Foo", in: [file("a.swift", new: contents)])
    #expect(results.count == 2)
    #expect(results.map(\.lineNumber) == [1, 2])
  }

  @Test func matchFileIDEqualsSearchableFileID() {
    let results = DiffSearchEngine.search(
      query: "x", in: [file("path/to/File.swift", new: "x marks it")])
    #expect(results.first?.fileID == "path/to/File.swift")
  }

  @Test func specialCharactersMatchLiterallyNotAsRegex() {
    let contents = "value a.b here\nvalue axb here"
    let results = DiffSearchEngine.search(query: "a.b", in: [file("a.swift", new: contents)])
    #expect(results.count == 1)
    #expect(results.first?.lineNumber == 1)
  }

  @Test func unicodeQueryMatches() {
    let contents = "标题 中文行\n表情 🎉 行\nplain line"
    let chineseHits = DiffSearchEngine.search(query: "中文", in: [file("a.swift", new: contents)])
    #expect(chineseHits.map(\.lineNumber) == [1])
    let emojiHits = DiffSearchEngine.search(query: "🎉", in: [file("a.swift", new: contents)])
    #expect(emojiHits.map(\.lineNumber) == [2])
  }

  @Test func addedFileSearchesOnlyNewContents() {
    let added = file("added.swift", old: "", new: "needle in new")
    let results = DiffSearchEngine.search(query: "needle", in: [added])
    #expect(results.count == 1)
    #expect(results.first?.side == .new)
  }

  @Test func deletedFileSearchesOnlyOldContents() {
    let deleted = file("deleted.swift", old: "needle in old", new: "")
    let results = DiffSearchEngine.search(query: "needle", in: [deleted])
    #expect(results.count == 1)
    #expect(results.first?.side == .old)
  }

  @Test func modifiedFileSearchesNewSideOnly() {
    // Same line on both sides must not double-report; modified searches new only.
    let modified = file("mod.swift", old: "needle context", new: "needle context")
    let results = DiffSearchEngine.search(query: "needle", in: [modified])
    #expect(results.count == 1)
    #expect(results.first?.side == .new)
  }

  @Test func longLineIsTruncatedInPreview() {
    let longLine = String(repeating: "a", count: 500) + "needle"
    let results = DiffSearchEngine.search(query: "needle", in: [file("a.swift", new: longLine)])
    #expect(results.count == 1)
    let preview = results.first?.lineText ?? ""
    #expect(preview.count == DiffSearchEngine.previewCharacterLimit + 1)  // +1 for the ellipsis
    #expect(preview.hasSuffix("…"))
  }

  @Test func lineNumbersAreOneBasedAcrossBoundaries() {
    let contents = "needle first\nmiddle\nmore\nneedle last"
    let results = DiffSearchEngine.search(query: "needle", in: [file("a.swift", new: contents)])
    #expect(results.map(\.lineNumber) == [1, 4])
    #expect(results.first?.lineText == "needle first")
    #expect(results.last?.lineText == "needle last")
  }

  @Test func blankLinesDoNotShiftLineNumbers() {
    let contents = "line1\n\n\nneedle on line4"
    let results = DiffSearchEngine.search(query: "needle", in: [file("a.swift", new: contents)])
    #expect(results.map(\.lineNumber) == [4])
  }

  @Test func matchIDsAreUniqueAcrossResults() {
    let contents = "needle\nneedle\nneedle"
    let results = DiffSearchEngine.search(
      query: "needle",
      in: [file("a.swift", new: contents), file("b.swift", new: contents)])
    let ids = Set(results.map(\.id))
    #expect(ids.count == results.count)
  }

  @Test func crlfLineEndingsAreStrippedFromPreview() {
    let contents = "needle one\r\nplain\r\nneedle two\r\n"
    let results = DiffSearchEngine.search(query: "needle", in: [file("a.swift", new: contents)])
    #expect(results.map(\.lineNumber) == [1, 3])
    #expect(results.map(\.lineText) == ["needle one", "needle two"])
    for match in results {
      #expect(!match.lineText.hasSuffix("\r"))
    }
  }

  @Test func multiMegabyteLineDoesNotRegressTruncation() {
    let hugeLine = String(repeating: "a", count: 2_000_000) + "needle"
    let results = DiffSearchEngine.search(query: "needle", in: [file("a.swift", new: hugeLine)])
    #expect(results.count == 1)
    let preview = results.first?.lineText ?? ""
    #expect(preview.count == DiffSearchEngine.previewCharacterLimit + 1)
    #expect(preview.hasSuffix("…"))
  }
}
