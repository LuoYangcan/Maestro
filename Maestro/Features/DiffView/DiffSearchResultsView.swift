import SwiftUI

/// The match list shown in the sidebar while a search query is active.
struct DiffSearchResultsView: View {
  let results: [DiffSearchMatch]
  let isLoading: Bool
  let onSelect: (DiffSearchMatch) -> Void

  var body: some View {
    if results.isEmpty {
      if isLoading {
        ContentUnavailableView {
          Label("Loading Changes…", systemImage: "arrow.triangle.2.circlepath")
        }
      } else {
        ContentUnavailableView(
          "No Results",
          systemImage: "magnifyingglass",
          description: Text("No changes match your search"),
        )
      }
    } else {
      List {
        ForEach(results) { match in
          Button {
            onSelect(match)
          } label: {
            DiffSearchResultRow(match: match)
          }
          .buttonStyle(.plain)
        }
      }
      .listStyle(.sidebar)
    }
  }
}

private struct DiffSearchResultRow: View {
  let match: DiffSearchMatch

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(match.fileDisplayName)
          .font(.body)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text("\(match.lineNumber)")
          .font(.caption)
          .monospaced()
          .foregroundStyle(.secondary)
      }
      Text(match.lineText)
        .font(.caption)
        .monospaced()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }
}
