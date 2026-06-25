import SwiftUI
import YiTong

struct DiffWindowContentView: View {
  var state: DiffWindowState
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
  @AppStorage("diffViewStyle") private var diffStyleRaw = DiffStyle.split.rawValue
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings
  @FocusState private var isSearchFocused: Bool

  private var isSearching: Bool {
    !state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var searchShortcut: KeyboardShortcut? {
    AppShortcuts.resolvedShortcut(for: AppShortcuts.CommandID.searchInDiff, in: resolvedKeybindings)?
      .keyboardShortcut
  }

  private var diffStyle: DiffStyle {
    DiffStyle(rawValue: diffStyleRaw) ?? .split
  }

  private var selectedFileID: Binding<String?> {
    Binding(
      get: { state.selectedFile?.id },
      set: { id in
        if let id, let file = state.changedFiles.first(where: { $0.id == id }) {
          state.selectFile(file)
        }
      },
    )
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      fileListSidebar
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
    } detail: {
      diffDetail
    }
    .background(searchFocusShortcut)
    .focusedSceneValue(\.toggleLeftSidebarAction, toggleSidebar)
    .toolbar(id: "diffToolbar") {
      ToolbarItem(id: "sidebarToggle", placement: .navigation) {
        Button {
          toggleSidebar()
        } label: {
          Image(systemName: "sidebar.left")
            .accessibilityLabel("Toggle Sidebar")
        }
        .help(
          AppShortcuts.helpText(
            title: "Toggle Sidebar",
            commandID: AppShortcuts.CommandID.toggleLeftSidebar,
            in: resolvedKeybindings
          ))
      }
      ToolbarItem(id: "diffStyle", placement: .primaryAction) {
        Picker("Diff Style", selection: $diffStyleRaw) {
          Image(systemName: "square.split.2x1")
            .accessibilityLabel("Split")
            .tag(DiffStyle.split.rawValue)
            .help("Split")
          Image(systemName: "text.justify.left")
            .accessibilityLabel("Unified")
            .tag(DiffStyle.unified.rawValue)
            .help("Unified")
        }
        .pickerStyle(.segmented)
        .help("Diff Style")
      }
    }
  }

  @ViewBuilder private var searchFocusShortcut: some View {
    if let searchShortcut {
      Button("Search in Changes") {
        if columnVisibility == .detailOnly {
          columnVisibility = .automatic
        }
        isSearchFocused = true
      }
      .keyboardShortcut(searchShortcut)
      .hidden()
    }
  }

  private func toggleSidebar() {
    withAnimation {
      columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
    }
  }

  // MARK: - Sidebar

  private var fileListSidebar: some View {
    VStack(spacing: 0) {
      searchField
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
      Divider()
      if isSearching {
        DiffSearchResultsView(
          results: state.searchResults,
          isLoading: state.isLoadingFiles,
          onSelect: state.selectMatch,
        )
      } else {
        fileList
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField("Search in changes", text: searchQueryBinding)
        .textFieldStyle(.plain)
        .focused($isSearchFocused)
        .help(
          AppShortcuts.helpText(
            title: "Search in Changes",
            commandID: AppShortcuts.CommandID.searchInDiff,
            in: resolvedKeybindings
          ))
      if isSearching {
        Button {
          searchQueryBinding.wrappedValue = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .accessibilityLabel("Clear Search")
        }
        .buttonStyle(.plain)
        .help("Clear Search")
      }
    }
  }

  private var searchQueryBinding: Binding<String> {
    Binding(
      get: { state.searchQuery },
      set: { newValue in
        state.searchQuery = newValue
        state.scheduleSearch()
      },
    )
  }

  private var fileList: some View {
    List(selection: selectedFileID) {
      ForEach(state.changedFiles) { file in
        FileRowView(file: file)
          .tag(file.id)
      }
    }
    .listStyle(.sidebar)
    .overlay {
      if state.isLoadingFiles && state.changedFiles.isEmpty {
        ProgressView()
      } else if !state.isLoadingFiles && state.changedFiles.isEmpty {
        ContentUnavailableView(
          "No Changes",
          systemImage: "checkmark.circle",
          description: Text("Working directory is clean"),
        )
      }
    }
  }

  // MARK: - Diff Detail

  private var diffDetail: some View {
    Group {
      if let document = state.diffDocument {
        DiffView(
          document: document,
          configuration: DiffConfiguration(
            style: diffStyle,
            showsFileHeaders: false,
          ),
        )
      } else if state.isLoadingFiles {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "Select a File",
          systemImage: "doc.text",
          description: Text("Choose a file from the sidebar to view changes"),
        )
      }
    }
  }
}

// MARK: - Status Color

extension DiffFileStatus {
  var color: Color {
    switch self {
    case .modified: .orange
    case .added: .green
    case .deleted: .red
    case .renamed: .blue
    case .copied: .blue
    case .unknown: .secondary
    }
  }
}

// MARK: - File Row

private struct FileRowView: View {
  let file: DiffChangedFile

  var body: some View {
    HStack(spacing: 6) {
      Text(file.statusSymbol)
        .font(.caption)
        .monospaced()
        .foregroundStyle(file.status.color)
        .frame(width: 14, alignment: .center)
      VStack(alignment: .leading, spacing: 1) {
        Text(file.displayName)
          .font(.body)
          .lineLimit(1)
        if !file.directoryPath.isEmpty {
          Text(file.directoryPath)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
        }
      }
    }
  }
}
