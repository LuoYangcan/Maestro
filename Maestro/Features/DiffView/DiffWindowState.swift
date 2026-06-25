import Foundation
import YiTong

@Observable
@MainActor
final class DiffWindowState {
  var worktreeURL: URL?
  var branchName: String = ""
  var changedFiles: [DiffChangedFile] = []
  var selectedFile: DiffChangedFile?
  var diffDocument: DiffDocument?
  var isLoadingFiles = false

  var searchQuery: String = ""
  var searchResults: [DiffSearchMatch] = []

  private var documentCache: [String: DiffDocument] = [:]
  private var loadTask: Task<Void, Never>?
  private var searchTask: Task<Void, Never>?

  func load(worktreeURL: URL, branchName: String) {
    self.worktreeURL = worktreeURL
    self.branchName = branchName
    changedFiles = []
    selectedFile = nil
    diffDocument = nil
    documentCache = [:]
    searchTask?.cancel()
    searchTask = nil
    loadTask?.cancel()
    loadTask = Task { await loadAllFiles(worktreeURL: worktreeURL) }
  }

  func refresh() {
    guard let worktreeURL else { return }
    documentCache = [:]
    searchTask?.cancel()
    searchTask = nil
    loadTask?.cancel()
    loadTask = Task { await loadAllFiles(worktreeURL: worktreeURL) }
  }

  func selectFile(_ file: DiffChangedFile) {
    guard selectedFile != file else { return }
    selectedFile = file
    diffDocument = documentCache[file.id]
  }

  // MARK: - Search

  /// Debounce window before a typed query triggers a full re-scan.
  private static let searchDebounce: Duration = .milliseconds(200)

  /// Schedules a debounced re-scan for the current `searchQuery`, so rapid
  /// typing doesn't re-scan every changed file's full text on every keystroke.
  /// Clearing the query resolves immediately.
  func scheduleSearch() {
    searchTask?.cancel()
    if searchQuery.isEmpty {
      searchTask = nil
      updateSearchResults()
      return
    }
    searchTask = Task { @MainActor in
      try? await ContinuousClock().sleep(for: Self.searchDebounce)
      guard !Task.isCancelled else { return }
      updateSearchResults()
    }
  }

  /// Runs the cross-file search for the current `searchQuery`, updating
  /// `searchResults`. An empty query clears the results. Called by the debounced
  /// `scheduleSearch` and directly after the cache rebuilds.
  func updateSearchResults() {
    searchResults = DiffSearchEngine.search(query: searchQuery, in: searchableFiles())
  }

  /// File-level jump (risk-2): select the file the match belongs to so the diff
  /// renders from the top with the sidebar selection synced. A `fileID` that no
  /// longer maps to a changed file (cache rebuilt) is a safe no-op.
  func selectMatch(_ match: DiffSearchMatch) {
    guard let file = changedFiles.first(where: { $0.id == match.fileID }) else { return }
    selectFile(file)
  }

  /// Assembles the searchable contents from `changedFiles` + the private cache.
  /// Files whose documents are not yet loaded are skipped (returns what is
  /// currently available), so searching mid-load returns partial / empty
  /// results without crashing.
  private func searchableFiles() -> [DiffSearchableFile] {
    changedFiles.compactMap { file in
      guard let diffFile = documentCache[file.id]?.files?.first else { return nil }
      return DiffSearchableFile(
        fileID: file.id,
        displayName: file.displayName,
        oldContents: diffFile.oldContents,
        newContents: diffFile.newContents,
      )
    }
  }

  // MARK: - Private

  private func loadAllFiles(worktreeURL: URL) async {
    isLoadingFiles = true
    async let trackedOutput = GitClient().diffNameStatus(at: worktreeURL)
    async let untrackedPaths = GitClient().untrackedFilePaths(at: worktreeURL)
    let trackedFiles = DiffChangedFile.parseNameStatus(await trackedOutput)
    let untrackedFiles = await untrackedPaths.map {
      DiffChangedFile(status: .added, oldPath: nil, newPath: $0)
    }
    let files = trackedFiles + untrackedFiles
    changedFiles = files

    // Load all documents concurrently
    let documents = await Self.loadAllDocuments(files: files, worktreeURL: worktreeURL)
    guard !Task.isCancelled else { return }
    documentCache = documents
    isLoadingFiles = false

    // Auto-select
    if let selectedFile, documents[selectedFile.id] != nil {
      diffDocument = documents[selectedFile.id]
    } else if let first = files.first {
      selectedFile = first
      diffDocument = documents[first.id]
    } else {
      selectedFile = nil
      diffDocument = nil
    }

    // Cache rebuilt: re-run any active search so results never reference
    // file IDs that no longer exist.
    if !searchQuery.isEmpty {
      updateSearchResults()
    }
  }

  private nonisolated static func loadAllDocuments(
    files: [DiffChangedFile],
    worktreeURL: URL
  ) async -> [String: DiffDocument] {
    await withTaskGroup(of: (String, DiffDocument).self) { group in
      for file in files {
        group.addTask {
          let doc = await loadDocument(for: file, worktreeURL: worktreeURL)
          return (file.id, doc)
        }
      }
      var result: [String: DiffDocument] = [:]
      for await (id, doc) in group {
        result[id] = doc
      }
      return result
    }
  }

  private nonisolated static func loadDocument(
    for file: DiffChangedFile,
    worktreeURL: URL
  ) async -> DiffDocument {
    let gitClient = GitClient()
    let oldContents: String
    let newContents: String

    switch file.status {
    case .added:
      oldContents = ""
      newContents = readFile(worktreeURL.appending(path: file.displayPath))
    case .deleted:
      oldContents = await gitClient.showFileAtHEAD(file.oldPath ?? "", in: worktreeURL) ?? ""
      newContents = ""
    case .renamed:
      oldContents = await gitClient.showFileAtHEAD(file.oldPath ?? "", in: worktreeURL) ?? ""
      newContents = readFile(worktreeURL.appending(path: file.newPath ?? ""))
    default:
      let path = file.displayPath
      oldContents = await gitClient.showFileAtHEAD(path, in: worktreeURL) ?? ""
      newContents = readFile(worktreeURL.appending(path: path))
    }

    let diffFile = DiffFile(
      oldPath: file.oldPath,
      newPath: file.newPath,
      oldContents: oldContents,
      newContents: newContents,
    )
    return DiffDocument(files: [diffFile], title: file.displayName)
  }

  private nonisolated static func readFile(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  }
}
