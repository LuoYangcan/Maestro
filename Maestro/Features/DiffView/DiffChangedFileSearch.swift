import Foundation

enum DiffChangedFileSearch {
  static func rankedFiles(_ files: [DiffChangedFile], query: String) -> [DiffChangedFile] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return files }

    let scorer = FuzzySearchScorer(query: trimmed)
    let matches = files.enumerated().compactMap { index, file -> ScoredFile? in
      guard let score = score(file: file, scorer: scorer, index: index) else { return nil }
      return score
    }

    return matches.sorted(by: ranksBefore).map(\.file)
  }

  private struct SearchField {
    let field: FuzzySearchScorer.Field
    let kind: FieldKind
  }

  private struct SearchFieldDescriptor {
    let text: String?
    let kind: FieldKind
    let weight: Int
    let prefixBonus: Int
    let contiguousBonus: Int
  }

  private enum FieldKind: Int {
    case basename
    case primaryPath
    case secondaryPath
    case status
  }

  private struct ScoredFile {
    let file: DiffChangedFile
    let score: Int
    let bestKind: FieldKind
    let prefixCount: Int
    let contiguousCount: Int
    let matchSpan: Int
    let index: Int
  }

  private static func score(file: DiffChangedFile, scorer: FuzzySearchScorer, index: Int) -> ScoredFile? {
    let fields = searchFields(for: file)
    guard let result = scorer.score(fields: fields.map(\.field)) else { return nil }
    let bestKind =
      result.fieldScores
      .map { fields[$0.fieldIndex].kind }
      .min { $0.rawValue < $1.rawValue } ?? .status
    let prefixCount = result.fieldScores.count { $0.isPrefix }
    let contiguousCount = result.fieldScores.count { $0.isContiguous }
    let matchSpan = result.fieldScores.reduce(0) { total, fieldScore in
      total
        + fieldScore.matches.reduce(0) { subtotal, match in
          subtotal + match.end - match.start
        }
    }
    return ScoredFile(
      file: file,
      score: result.score,
      bestKind: bestKind,
      prefixCount: prefixCount,
      contiguousCount: contiguousCount,
      matchSpan: matchSpan,
      index: index
    )
  }

  private static func ranksBefore(_ lhs: ScoredFile, _ rhs: ScoredFile) -> Bool {
    if lhs.bestKind != rhs.bestKind {
      return lhs.bestKind.rawValue < rhs.bestKind.rawValue
    }
    if lhs.prefixCount != rhs.prefixCount {
      return lhs.prefixCount > rhs.prefixCount
    }
    if lhs.contiguousCount != rhs.contiguousCount {
      return lhs.contiguousCount > rhs.contiguousCount
    }
    if lhs.score != rhs.score {
      return lhs.score > rhs.score
    }
    if lhs.matchSpan != rhs.matchSpan {
      return lhs.matchSpan < rhs.matchSpan
    }
    return lhs.index < rhs.index
  }

  private static func searchFields(for file: DiffChangedFile) -> [SearchField] {
    var fields: [SearchField] = []
    appendField(
      SearchFieldDescriptor(
        text: file.displayName,
        kind: .basename,
        weight: 120,
        prefixBonus: 200_000,
        contiguousBonus: 80_000
      ),
      to: &fields
    )
    appendField(
      SearchFieldDescriptor(
        text: file.displayPath,
        kind: .primaryPath,
        weight: 70,
        prefixBonus: 40_000,
        contiguousBonus: 20_000
      ),
      to: &fields
    )
    appendField(
      SearchFieldDescriptor(
        text: file.directoryPath,
        kind: .primaryPath,
        weight: 60,
        prefixBonus: 25_000,
        contiguousBonus: 12_000
      ),
      to: &fields
    )
    appendField(
      SearchFieldDescriptor(
        text: file.oldPath,
        kind: .secondaryPath,
        weight: 55,
        prefixBonus: 20_000,
        contiguousBonus: 10_000
      ),
      to: &fields
    )
    appendField(
      SearchFieldDescriptor(
        text: file.newPath,
        kind: .secondaryPath,
        weight: 55,
        prefixBonus: 20_000,
        contiguousBonus: 10_000
      ),
      to: &fields
    )
    for statusText in file.status.searchTerms {
      appendField(
        SearchFieldDescriptor(
          text: statusText,
          kind: .status,
          weight: 15,
          prefixBonus: 2_000,
          contiguousBonus: 1_000
        ),
        to: &fields
      )
    }
    return fields
  }

  private static func appendField(
    _ descriptor: SearchFieldDescriptor,
    to fields: inout [SearchField]
  ) {
    let text = descriptor.text
    guard let text, !text.isEmpty else { return }
    if fields.contains(where: { $0.field.text == text }) {
      return
    }
    fields.append(
      SearchField(
        field: FuzzySearchScorer.Field(
          text: text,
          weight: descriptor.weight,
          prefixBonus: descriptor.prefixBonus,
          contiguousBonus: descriptor.contiguousBonus
        ),
        kind: descriptor.kind
      )
    )
  }
}

extension DiffFileStatus {
  fileprivate var searchTerms: [String] {
    switch self {
    case .modified:
      ["M", "modified", "changed"]
    case .added:
      ["A", "added", "new", "untracked"]
    case .deleted:
      ["D", "deleted", "removed"]
    case .renamed:
      ["R", "renamed", "moved"]
    case .copied:
      ["C", "copied"]
    case .unknown:
      ["?", "unknown"]
    }
  }
}
