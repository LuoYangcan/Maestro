import Foundation

/// Which side of a file a match was found in.
nonisolated enum DiffSearchSide: Sendable {
  case old
  case new
}

/// A single literal-substring hit within one changed file.
nonisolated struct DiffSearchMatch: Identifiable, Equatable, Sendable {
  /// Stable, unique within a result set: fileID + side + line + ordinal.
  let id: String
  /// == `DiffChangedFile.id` == displayPath; callers use it to select the file.
  let fileID: String
  let fileDisplayName: String
  let side: DiffSearchSide
  /// 1-based line number within the matched side's contents.
  let lineNumber: Int
  /// The matched line's text (truncated for preview when very long).
  let lineText: String
}

/// The searchable contents of one changed file, decoupled from the window state.
nonisolated struct DiffSearchableFile: Equatable, Sendable {
  let fileID: String
  let displayName: String
  /// Empty when the file was added.
  let oldContents: String
  /// Empty when the file was deleted.
  let newContents: String
}

/// Pure-logic, cross-file literal substring search over changed-file contents.
///
/// Searches the full text of each changed file (including unchanged context),
/// preferring `newContents`: an added file searches `newContents`, a deleted
/// file searches `oldContents`, and an otherwise-modified file searches
/// `newContents` only (its `oldContents` is ignored to avoid double-reporting
/// unchanged lines that appear on both sides).
nonisolated enum DiffSearchEngine {
  /// Preview lines longer than this are truncated.
  static let previewCharacterLimit = 200

  static func search(query: String, in files: [DiffSearchableFile]) -> [DiffSearchMatch] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return [] }

    var matches: [DiffSearchMatch] = []
    var ordinal = 0

    for file in files {
      let side: DiffSearchSide = file.newContents.isEmpty ? .old : .new
      let contents = side == .new ? file.newContents : file.oldContents
      guard !contents.isEmpty else { continue }

      // Split on the `\n` scalar, not the Character: a CRLF file joins `\r\n`
      // into one grapheme, so a Character-level split would not break lines at
      // all. Scalar slices map back to `Substring` without copying.
      let lines = contents.unicodeScalars
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { Substring($0) }
      for (index, line) in lines.enumerated() {
        guard line.range(of: trimmedQuery, options: .caseInsensitive) != nil else { continue }
        let lineNumber = index + 1
        matches.append(
          DiffSearchMatch(
            id: "\(file.fileID)#\(side)#\(lineNumber)#\(ordinal)",
            fileID: file.fileID,
            fileDisplayName: file.displayName,
            side: side,
            lineNumber: lineNumber,
            lineText: preview(of: line),
          ))
        ordinal += 1
      }
    }

    return matches
  }

  private static func preview(of line: Substring) -> String {
    // Drop a trailing CR so Windows `\r\n` endings don't leak into the preview.
    let trimmed = line.last == "\r" ? line.dropLast() : line
    // Compare against a bounded prefix instead of counting the whole line, so a
    // multi-megabyte single line isn't scanned end-to-end just to truncate it.
    let prefix = trimmed.prefix(previewCharacterLimit + 1)
    guard prefix.count > previewCharacterLimit else { return String(trimmed) }
    return String(prefix.prefix(previewCharacterLimit)) + "…"
  }
}
