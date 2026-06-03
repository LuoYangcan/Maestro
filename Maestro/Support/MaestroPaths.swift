import Foundation

nonisolated enum MaestroPaths {
  static var baseDirectory: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let maestroDir = home.appending(path: ".maestro", directoryHint: .isDirectory)
    copyLegacyBaseDirectoryIfNeeded(to: maestroDir, home: home)
    return maestroDir
  }

  private static var legacyProwlDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: ".prowl", directoryHint: .isDirectory)
  }

  private static var legacySupacodeDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: ".supacode", directoryHint: .isDirectory)
  }

  static var repositorySettingsDirectory: URL {
    baseDirectory.appending(path: "repo", directoryHint: .isDirectory)
  }

  static var appSupportDirectory: URL {
    let appSupport =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? baseDirectory
    return
      appSupport
      .appending(path: "com.yangcanluo.maestro", directoryHint: .isDirectory)
      .standardizedFileURL
  }

  static var cacheDirectory: URL {
    appSupportDirectory.appending(path: "cache", directoryHint: .isDirectory)
  }

  static var reposDirectory: URL {
    baseDirectory.appending(path: "repos", directoryHint: .isDirectory)
  }

  static func repositoryDirectory(for rootURL: URL) -> URL {
    let name = repositoryDirectoryName(for: rootURL)
    return reposDirectory.appending(path: name, directoryHint: .isDirectory)
  }

  static func normalizedWorktreeBaseDirectoryPath(
    _ rawPath: String?,
    repositoryRootURL: URL? = nil
  ) -> String? {
    guard let rawPath else {
      return nil
    }
    return PathPolicy.normalizePath(
      rawPath,
      relativeTo: repositoryRootURL,
      resolvingSymlinks: false
    )
  }

  static func worktreeBaseDirectory(
    for repositoryRootURL: URL,
    globalDefaultPath: String?,
    repositoryOverridePath: String?
  ) -> URL {
    let rootURL = repositoryRootURL.standardizedFileURL
    if let repositoryOverridePath = normalizedWorktreeBaseDirectoryPath(
      repositoryOverridePath,
      repositoryRootURL: rootURL
    ) {
      return PathPolicy.normalizeURL(
        URL(filePath: repositoryOverridePath, directoryHint: .isDirectory),
        resolvingSymlinks: false
      )
    }
    if let globalDefaultPath = normalizedWorktreeBaseDirectoryPath(globalDefaultPath) {
      return PathPolicy.normalizeURL(
        URL(filePath: globalDefaultPath, directoryHint: .isDirectory),
        resolvingSymlinks: false
      )
      .appending(path: repositoryDirectoryName(for: rootURL), directoryHint: .isDirectory)
      .standardizedFileURL
    }
    return repositoryDirectory(for: rootURL)
  }

  static func exampleWorktreePath(
    for repositoryRootURL: URL,
    globalDefaultPath: String?,
    repositoryOverridePath: String?,
    branchName: String = "swift-otter"
  ) -> String {
    worktreeBaseDirectory(
      for: repositoryRootURL,
      globalDefaultPath: globalDefaultPath,
      repositoryOverridePath: repositoryOverridePath
    )
    .appending(path: branchName, directoryHint: .isDirectory)
    .standardizedFileURL
    .path(percentEncoded: false)
  }

  static var settingsURL: URL {
    baseDirectory.appending(path: "settings.json", directoryHint: .notDirectory)
  }

  static var repositorySnapshotURL: URL {
    cacheDirectory.appending(path: "repository-snapshot.json", directoryHint: .notDirectory)
  }

  static var terminalLayoutSnapshotURL: URL {
    cacheDirectory.appending(path: "terminal-layout-snapshot.json", directoryHint: .notDirectory)
  }

  static var repositoryEntriesURL: URL {
    baseDirectory.appending(path: "repository-entries.json", directoryHint: .notDirectory)
  }

  static var repositoryAppearancesURL: URL {
    baseDirectory.appending(path: "repository-appearances.json", directoryHint: .notDirectory)
  }

  /// Directory where user-imported repository icon images live, scoped
  /// per-repo so cleanup is automatic when the per-repo settings
  /// directory is removed.
  static func repositoryIconsDirectory(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL)
      .appending(path: "icons", directoryHint: .isDirectory)
  }

  /// Resolved file URL for a stored icon filename. The filename is the
  /// only thing persisted in `RepositoryAppearance` so that moving a
  /// repository (or renaming its directory) leaves the artifact alone.
  static func repositoryIconFileURL(filename: String, repositoryRootURL rootURL: URL) -> URL {
    repositoryIconsDirectory(for: rootURL)
      .appending(path: filename, directoryHint: .notDirectory)
  }

  static func migrateLegacyCacheFilesIfNeeded(
    fileManager: FileManager = .default,
    legacyDirectory: URL? = nil,
    cacheDirectory: URL? = nil
  ) throws {
    let destinationDirectory = (cacheDirectory ?? self.cacheDirectory).standardizedFileURL
    try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

    let fileNames = [
      "repository-snapshot.json",
      "terminal-layout-snapshot.json",
    ]

    let sourceDirectories =
      legacyDirectory.map { [$0.standardizedFileURL] }
      ?? [
        baseDirectory.standardizedFileURL,
        legacyProwlDirectory.standardizedFileURL,
        legacySupacodeDirectory.standardizedFileURL,
      ]

    for sourceDirectory in sourceDirectories {
      for name in fileNames {
        let legacyURL = sourceDirectory.appending(path: name, directoryHint: .notDirectory)
        let destinationURL = destinationDirectory.appending(path: name, directoryHint: .notDirectory)
        guard !fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) else {
          continue
        }
        guard fileManager.fileExists(atPath: legacyURL.path(percentEncoded: false)) else {
          continue
        }
        do {
          try fileManager.moveItem(at: legacyURL, to: destinationURL)
        } catch {
          try fileManager.copyItem(at: legacyURL, to: destinationURL)
          do {
            try fileManager.removeItem(at: legacyURL)
          } catch {
            SupaLogger("Paths").warning(
              "Unable to remove migrated cache file at \(legacyURL): \(error.localizedDescription)"
            )
          }
        }
      }
    }
  }

  static func repositorySettingsURL(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL)
      .appending(path: "maestro.json", directoryHint: .notDirectory)
  }

  static func userRepositorySettingsURL(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL)
      .appending(path: "maestro.onevcat.json", directoryHint: .notDirectory)
  }

  static func legacyRepositorySettingsURLs(for rootURL: URL) -> [URL] {
    [
      legacyProwlRepositorySettingsURL(for: rootURL),
      legacySupacodeRepositorySettingsURL(for: rootURL),
      originalLegacyRepositorySettingsURL(for: rootURL),
    ]
  }

  static func legacyUserRepositorySettingsURLs(for rootURL: URL) -> [URL] {
    [
      legacyProwlUserRepositorySettingsURL(for: rootURL),
      legacySupacodeUserRepositorySettingsURL(for: rootURL),
      originalLegacyUserRepositorySettingsURL(for: rootURL),
    ]
  }

  /// Legacy location: ~/.prowl/repo/<name>/prowl.json
  static func legacyRepositorySettingsURL(for rootURL: URL) -> URL {
    legacyProwlRepositorySettingsURL(for: rootURL)
  }

  /// Legacy location: ~/.prowl/repo/<name>/prowl.onevcat.json
  static func legacyUserRepositorySettingsURL(for rootURL: URL) -> URL {
    legacyProwlUserRepositorySettingsURL(for: rootURL)
  }

  private static func legacyProwlRepositorySettingsURL(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL, baseDirectory: legacyProwlDirectory)
      .appending(path: "prowl.json", directoryHint: .notDirectory)
  }

  private static func legacyProwlUserRepositorySettingsURL(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL, baseDirectory: legacyProwlDirectory)
      .appending(path: "prowl.onevcat.json", directoryHint: .notDirectory)
  }

  /// Legacy location: ~/.supacode/repo/<name>/supacode.json
  private static func legacySupacodeRepositorySettingsURL(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL, baseDirectory: legacySupacodeDirectory)
      .appending(path: "supacode.json", directoryHint: .notDirectory)
  }

  /// Legacy location: ~/.supacode/repo/<name>/supacode.onevcat.json
  private static func legacySupacodeUserRepositorySettingsURL(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL, baseDirectory: legacySupacodeDirectory)
      .appending(path: "supacode.onevcat.json", directoryHint: .notDirectory)
  }

  /// Legacy location: <repo-root>/supacode.json (original upstream location)
  static func originalLegacyRepositorySettingsURL(for rootURL: URL) -> URL {
    rootURL.standardizedFileURL.appending(path: "supacode.json", directoryHint: .notDirectory)
  }

  /// Legacy location: <repo-root>/supacode.onevcat.json (original upstream location)
  static func originalLegacyUserRepositorySettingsURL(for rootURL: URL) -> URL {
    rootURL.standardizedFileURL.appending(path: "supacode.onevcat.json", directoryHint: .notDirectory)
  }

  private static func repositorySettingsDirectory(for rootURL: URL) -> URL {
    repositorySettingsDirectory(for: rootURL, baseDirectory: baseDirectory)
  }

  private static func repositorySettingsDirectory(for rootURL: URL, baseDirectory: URL) -> URL {
    let name = repositorySettingsDirectoryName(for: rootURL)
    return
      baseDirectory
      .appending(path: "repo", directoryHint: .isDirectory)
      .appending(path: name, directoryHint: .isDirectory)
  }

  private static func copyLegacyBaseDirectoryIfNeeded(to maestroDir: URL, home: URL) {
    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: maestroDir.path(percentEncoded: false)) else {
      return
    }
    let sources = [
      home.appending(path: ".prowl", directoryHint: .isDirectory),
      home.appending(path: ".supacode", directoryHint: .isDirectory),
    ]
    guard let source = sources.first(where: { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }) else {
      return
    }
    do {
      try fileManager.copyItem(at: source, to: maestroDir)
    } catch {
      SupaLogger("Paths").warning(
        "Unable to migrate legacy base directory from \(source.path(percentEncoded: false)) to "
          + "\(maestroDir.path(percentEncoded: false)): \(error.localizedDescription)"
      )
    }
  }

  private static func repositoryDirectoryName(for rootURL: URL) -> String {
    let repoName = rootURL.lastPathComponent
    if repoName.isEmpty || repoName == ".bare" || repoName == ".git" {
      let path = rootURL.standardizedFileURL.path(percentEncoded: false)
      let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      if trimmed.isEmpty {
        return "_"
      }
      return trimmed.replacing("/", with: "_")
    }
    return repoName
  }

  private static func repositorySettingsDirectoryName(for rootURL: URL) -> String {
    let repoName = rootURL.standardizedFileURL.lastPathComponent
    if repoName.isEmpty || repoName == "/" {
      return "_"
    }
    return repoName
  }
}
