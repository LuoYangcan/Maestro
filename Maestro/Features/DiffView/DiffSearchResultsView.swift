import SwiftUI

/// The match list shown in the sidebar while a search query is active.
///
/// Only rendered for `DiffSidebarContent.contentMatches`, which the state
/// emits solely when there are matches or a load is still in flight — so an
/// empty `results` set here always means "still loading". The genuine
/// "no matches" state is owned by `DiffSidebarContent.noResults` upstream.
struct DiffSearchResultsView: View {
  let results: [DiffSearchMatch]
  let onSelect: (DiffSearchMatch) -> Void

  var body: some View {
    if results.isEmpty {
      ContentUnavailableView {
        Label("Loading Changes…", systemImage: "arrow.triangle.2.circlepath")
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
