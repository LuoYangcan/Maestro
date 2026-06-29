import Foundation

struct FuzzySearchScorer: Sendable {
  struct QueryPiece: Sendable {
    let normalized: String
    let normalizedLowercase: String
    let expectContiguousMatch: Bool
  }

  struct PreparedQuery: Sendable {
    let piece: QueryPiece
    let values: [QueryPiece]?

    var pieces: [QueryPiece] {
      values ?? [piece]
    }
  }

  struct Match: Hashable, Sendable {
    var start: Int
    var end: Int
  }

  struct TextScore: Sendable {
    let score: Int
    let positions: [Int]

    var matches: [Match] {
      FuzzySearchScorer.createMatches(positions)
    }
  }

  struct Field: Sendable {
    let text: String
    let weight: Int
    let prefixBonus: Int
    let contiguousBonus: Int

    init(
      text: String,
      weight: Int = 1,
      prefixBonus: Int = 0,
      contiguousBonus: Int = 0
    ) {
      self.text = text
      self.weight = weight
      self.prefixBonus = prefixBonus
      self.contiguousBonus = contiguousBonus
    }
  }

  struct FieldScore: Sendable {
    let fieldIndex: Int
    let score: Int
    let matches: [Match]
    let isPrefix: Bool
    let isContiguous: Bool
  }

  struct Result: Sendable {
    let score: Int
    let fieldScores: [FieldScore]
  }

  let preparedQuery: PreparedQuery
  private let allowNonContiguousMatches: Bool

  init(query: String, allowNonContiguousMatches: Bool = true) {
    preparedQuery = Self.prepareQuery(query)
    self.allowNonContiguousMatches = allowNonContiguousMatches
  }

  func score(fields: [Field]) -> Result? {
    guard !preparedQuery.piece.normalized.isEmpty else { return nil }
    var totalScore = 0
    var fieldScores: [FieldScore] = []

    for piece in preparedQuery.pieces {
      let scores = fields.enumerated().compactMap { index, field in
        score(field: field, index: index, piece: piece)
      }
      guard let best = scores.max(by: compareFieldScores) else { return nil }
      totalScore += best.score
      fieldScores.append(best)
    }

    return Result(score: totalScore, fieldScores: fieldScores)
  }

  func score(target: String, piece: QueryPiece) -> TextScore? {
    if target.isEmpty || piece.normalized.isEmpty {
      return nil
    }

    let targetChars = Array(target)
    let queryChars = Array(piece.normalized)

    if targetChars.count < queryChars.count {
      return nil
    }

    let targetLower = Array(target.lowercased())
    let queryLower = Array(piece.normalizedLowercase)
    let result = doScoreFuzzy(
      query: queryChars,
      queryLower: queryLower,
      target: targetChars,
      targetLower: targetLower,
      allowNonContiguousMatches: allowNonContiguousMatches && !piece.expectContiguousMatch
    )
    guard result.score > 0 else { return nil }
    return TextScore(score: result.score, positions: result.positions)
  }

  func prefixMatches(for piece: QueryPiece, in target: String) -> [Match]? {
    let targetLower = target.lowercased()
    guard targetLower.hasPrefix(piece.normalizedLowercase) else { return nil }
    return [Match(start: 0, end: piece.normalized.count)]
  }

  static func normalizeMatches(_ matches: [Match]) -> [Match]? {
    guard !matches.isEmpty else { return nil }

    let sortedMatches = matches.sorted { $0.start < $1.start }
    var normalizedMatches: [Match] = []
    var currentMatch: Match?

    for match in sortedMatches {
      if let existing = currentMatch, matchOverlaps(existing, match) {
        let merged = Match(
          start: min(existing.start, match.start),
          end: max(existing.end, match.end)
        )
        currentMatch = merged
        normalizedMatches[normalizedMatches.count - 1] = merged
      } else {
        currentMatch = match
        normalizedMatches.append(match)
      }
    }

    return normalizedMatches
  }

  private func score(field: Field, index: Int, piece: QueryPiece) -> FieldScore? {
    guard let textScore = score(target: field.text, piece: piece) else { return nil }
    let matches = textScore.matches
    let isPrefix = prefixMatches(for: piece, in: field.text) != nil
    let isContiguous = matches.count == 1 && matches[0].end - matches[0].start == piece.normalized.count
    var score = textScore.score * field.weight
    if isPrefix {
      score += field.prefixBonus
    }
    if isContiguous {
      score += field.contiguousBonus
    }
    return FieldScore(
      fieldIndex: index,
      score: score,
      matches: matches,
      isPrefix: isPrefix,
      isContiguous: isContiguous
    )
  }

  private func compareFieldScores(_ lhs: FieldScore, _ rhs: FieldScore) -> Bool {
    if lhs.score != rhs.score {
      return lhs.score < rhs.score
    }
    if lhs.isPrefix != rhs.isPrefix {
      return !lhs.isPrefix && rhs.isPrefix
    }
    if lhs.isContiguous != rhs.isContiguous {
      return !lhs.isContiguous && rhs.isContiguous
    }
    return lhs.fieldIndex > rhs.fieldIndex
  }

  private func doScoreFuzzy(
    query: [Character],
    queryLower: [Character],
    target: [Character],
    targetLower: [Character],
    allowNonContiguousMatches: Bool
  ) -> (score: Int, positions: [Int]) {
    let queryLength = query.count
    let targetLength = target.count
    var scores = Array(repeating: 0, count: queryLength * targetLength)
    var matches = Array(repeating: 0, count: queryLength * targetLength)

    for queryIndex in 0..<queryLength {
      let queryIndexOffset = queryIndex * targetLength
      let queryIndexPreviousOffset = queryIndexOffset - targetLength
      let queryIndexGtNull = queryIndex > 0

      let queryCharAtIndex = query[queryIndex]
      let queryLowerCharAtIndex = queryLower[queryIndex]

      for targetIndex in 0..<targetLength {
        let targetIndexGtNull = targetIndex > 0

        let currentIndex = queryIndexOffset + targetIndex
        let leftIndex = currentIndex - 1
        let diagIndex = queryIndexPreviousOffset + targetIndex - 1

        let leftScore = targetIndexGtNull ? scores[leftIndex] : 0
        let diagScore = queryIndexGtNull && targetIndexGtNull ? scores[diagIndex] : 0
        let matchesSequenceLength = queryIndexGtNull && targetIndexGtNull ? matches[diagIndex] : 0

        let score: Int
        let scoreContext = CharScoreContext(
          queryChar: queryCharAtIndex,
          queryLowerChar: queryLowerCharAtIndex,
          target: target,
          targetLower: targetLower,
          targetIndex: targetIndex,
          matchesSequenceLength: matchesSequenceLength
        )
        if diagScore != 0 && queryIndexGtNull {
          score = computeCharScore(scoreContext)
        } else if queryIndexGtNull {
          score = 0
        } else {
          score = computeCharScore(scoreContext)
        }

        let isValidScore = score > 0 && diagScore + score >= leftScore

        if isValidScore
          && (allowNonContiguousMatches || queryIndexGtNull || startsWith(targetLower, queryLower, at: targetIndex))
        {
          matches[currentIndex] = matchesSequenceLength + 1
          scores[currentIndex] = diagScore + score
        } else {
          matches[currentIndex] = 0
          scores[currentIndex] = leftScore
        }
      }
    }

    var positions: [Int] = []
    var queryIndex = queryLength - 1
    var targetIndex = targetLength - 1
    while queryIndex >= 0 && targetIndex >= 0 {
      let currentIndex = queryIndex * targetLength + targetIndex
      let match = matches[currentIndex]
      if match == 0 {
        targetIndex -= 1
      } else {
        positions.append(targetIndex)
        queryIndex -= 1
        targetIndex -= 1
      }
    }

    positions.reverse()
    return (scores[queryLength * targetLength - 1], positions)
  }

  private struct CharScoreContext {
    let queryChar: Character
    let queryLowerChar: Character
    let target: [Character]
    let targetLower: [Character]
    let targetIndex: Int
    let matchesSequenceLength: Int
  }

  private func computeCharScore(_ context: CharScoreContext) -> Int {
    if !considerAsEqual(context.queryLowerChar, context.targetLower[context.targetIndex]) {
      return 0
    }

    var score = 1

    if context.matchesSequenceLength > 0 {
      score += min(context.matchesSequenceLength, 3) * 6
      score += max(0, context.matchesSequenceLength - 3) * 3
    }

    if context.queryChar == context.target[context.targetIndex] {
      score += 1
    }

    if context.targetIndex == 0 {
      score += 8
    } else {
      let separatorBonus = scoreSeparatorAtPos(context.target[context.targetIndex - 1])
      if separatorBonus > 0 {
        score += separatorBonus
      } else if isUpper(context.target[context.targetIndex]) && context.matchesSequenceLength == 0 {
        score += 2
      }
    }

    return score
  }

  private func considerAsEqual(_ lhs: Character, _ rhs: Character) -> Bool {
    if lhs == rhs {
      return true
    }
    if lhs == "/" || lhs == "\\" {
      return rhs == "/" || rhs == "\\"
    }
    return false
  }

  private func scoreSeparatorAtPos(_ char: Character) -> Int {
    switch char {
    case "/", "\\":
      return 5
    case "_", "-", ".", " ", "'", "\"", ":":
      return 4
    default:
      return 0
    }
  }

  private func isUpper(_ char: Character) -> Bool {
    guard let scalar = String(char).unicodeScalars.first else { return false }
    return scalar.properties.isUppercase
  }

  private func startsWith(_ target: [Character], _ query: [Character], at index: Int) -> Bool {
    guard index + query.count <= target.count else { return false }
    for queryIndex in 0..<query.count where target[index + queryIndex] != query[queryIndex] {
      return false
    }
    return true
  }

  private static func createMatches(_ offsets: [Int]) -> [Match] {
    var matches: [Match] = []
    var lastMatch: Match?

    for position in offsets {
      if var lastMatch, lastMatch.end == position {
        lastMatch.end += 1
        matches[matches.count - 1] = lastMatch
      } else {
        let match = Match(start: position, end: position + 1)
        matches.append(match)
        lastMatch = match
      }
    }

    return matches
  }

  private static func matchOverlaps(_ matchA: Match, _ matchB: Match) -> Bool {
    if matchA.end < matchB.start {
      return false
    }
    if matchB.end < matchA.start {
      return false
    }
    return true
  }

  private static func prepareQuery(_ original: String) -> PreparedQuery {
    let expectContiguousMatch = queryExpectsExactMatch(original)
    let normalized = normalizeQuery(original)
    let piece = QueryPiece(
      normalized: normalized.normalized,
      normalizedLowercase: normalized.normalizedLowercase,
      expectContiguousMatch: expectContiguousMatch
    )

    let splitPieces = original.split(separator: " ")
    var values: [QueryPiece] = []
    if splitPieces.count > 1 {
      for pieceValue in splitPieces {
        let value = String(pieceValue)
        let expectExactMatchPiece = queryExpectsExactMatch(value)
        let normalizedPiece = normalizeQuery(value)
        if normalizedPiece.normalized.isEmpty {
          continue
        }
        values.append(
          QueryPiece(
            normalized: normalizedPiece.normalized,
            normalizedLowercase: normalizedPiece.normalizedLowercase,
            expectContiguousMatch: expectExactMatchPiece
          )
        )
      }
    }

    return PreparedQuery(piece: piece, values: values.isEmpty ? nil : values)
  }

  private static func normalizeQuery(_ original: String) -> (normalized: String, normalizedLowercase: String) {
    var pathNormalized = String()
    pathNormalized.reserveCapacity(original.count)
    for char in original {
      if char == "\\" {
        pathNormalized.append("/")
      } else {
        pathNormalized.append(char)
      }
    }

    var normalized = String()
    normalized.reserveCapacity(pathNormalized.count)
    for char in pathNormalized {
      if char == "*" || char == "…" || char == "\"" || char.isWhitespace {
        continue
      }
      normalized.append(char)
    }

    if normalized.count > 1, normalized.hasSuffix("#") {
      normalized.removeLast()
    }

    return (normalized, normalized.lowercased())
  }

  private static func queryExpectsExactMatch(_ query: String) -> Bool {
    query.hasPrefix("\"") && query.hasSuffix("\"")
  }
}
