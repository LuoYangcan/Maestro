import Testing

@testable import Maestro

struct FuzzySearchScorerTests {
  @Test func matchesPascalCaseBasenameWithCompressedQuery() {
    let scorer = FuzzySearchScorer(query: "isfileconne")

    let result = scorer.score(fields: [
      FuzzySearchScorer.Field(text: "IsFileConnected.swift")
    ])

    #expect(result != nil)
  }

  @Test func treatsSlashAndBackslashAsEquivalent() {
    let scorer = FuzzySearchScorer(query: "Features\\Diff")

    let result = scorer.score(fields: [
      FuzzySearchScorer.Field(text: "Maestro/Features/DiffView/DiffWindowContentView.swift")
    ])

    #expect(result != nil)
  }

  @Test func requiresEveryQueryPieceToMatch() {
    let matching = FuzzySearchScorer(query: "features diff")
    let missingPiece = FuzzySearchScorer(query: "features zzz")
    let fields = [
      FuzzySearchScorer.Field(text: "Maestro/Features/DiffView/DiffWindowContentView.swift")
    ]

    #expect(matching.score(fields: fields) != nil)
    #expect(missingPiece.score(fields: fields) == nil)
  }

  @Test func matchesCamelSubsequence() {
    let scorer = FuzzySearchScorer(query: "cpf")

    let result = scorer.score(fields: [
      FuzzySearchScorer.Field(text: "CommandPaletteFeature.swift")
    ])

    #expect(result != nil)
  }

  @Test func allowsMissingCharactersInQuerySubsequence() {
    let scorer = FuzzySearchScorer(query: "serch")

    let result = scorer.score(fields: [
      FuzzySearchScorer.Field(text: "SearchMatcher.swift")
    ])

    #expect(result != nil)
  }

  @Test func fieldWeightCanChooseTheBestMatchingField() throws {
    let scorer = FuzzySearchScorer(query: "diff")
    let result = try #require(
      scorer.score(fields: [
        FuzzySearchScorer.Field(text: "Maestro/Features/DiffView", weight: 1),
        FuzzySearchScorer.Field(text: "DiffWindowContentView.swift", weight: 20),
      ])
    )

    #expect(result.fieldScores.first?.fieldIndex == 1)
  }
}
