import Foundation
import UniformTypeIdentifiers

/// A link that terminal output asked to open (OSC 8 hyperlink or a `link`
/// config match). libghostty 1.4 refuses to open these kinds itself on macOS
/// and delegates checking to the embedder.
nonisolated struct TerminalLink: Equatable, Sendable {
  enum DenialReason: Equatable, Sendable {
    case malformedURL
    case unsafeCharacters
    case invalidWebURL
    case inaccessibleFile
    case unsafeFile

    var message: String {
      switch self {
      case .malformedURL:
        String(localized: "The target is not an absolute URL with a scheme.")
      case .unsafeCharacters:
        String(localized: "The target contains invisible or line-breaking characters.")
      case .invalidWebURL:
        String(localized: "The web target does not contain a valid host.")
      case .inaccessibleFile:
        String(localized: "The local target does not exist or is not a regular file or folder.")
      case .unsafeFile:
        String(localized: "Opening this local target could run code.")
      }
    }
  }

  enum Decision: Equatable, Sendable {
    case allow(URL)
    case confirm(URL)
    case deny(DenialReason)
  }

  let string: String

  init(_ string: String) {
    self.string = string
  }

  init(unknownKindValue value: String) {
    if URL(string: value)?.scheme != nil || Self.containsUnsafeCharacters(value) {
      self.init(value)
    } else {
      let path = NSString(string: value).standardizingPath
      self.init(URL(filePath: path).absoluteString)
    }
  }

  var decision: Decision {
    guard !string.isEmpty else { return .deny(.malformedURL) }
    guard !Self.containsUnsafeCharacters(string) else {
      return .deny(.unsafeCharacters)
    }
    guard
      let url = URL(string: string),
      let scheme = url.scheme?.lowercased(),
      !scheme.isEmpty
    else {
      return .deny(.malformedURL)
    }

    switch scheme {
    case "http", "https":
      guard let host = url.host(), !host.isEmpty else {
        return .deny(.invalidWebURL)
      }
      return .allow(url)

    case "mailto":
      guard
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        !components.path.isEmpty
      else {
        return .deny(.malformedURL)
      }
      return .allow(url)

    case "file":
      return Self.fileDecision(for: url)

    default:
      return .confirm(url)
    }
  }

  var displayString: String {
    let normalized: String
    if let url = URL(string: string), url.scheme != nil {
      if url.isFileURL {
        let effective = Self.effectiveFileURL(url) ?? url.standardizedFileURL.resolvingSymlinksInPath()
        normalized = effective.path(percentEncoded: false)
      } else {
        normalized = string
      }
    } else {
      normalized = URL(filePath: string).standardizedFileURL.path(percentEncoded: false)
    }
    var result = ""
    for scalar in normalized.unicodeScalars {
      if Self.isUnsafeCharacter(scalar) {
        result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
      } else {
        result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  static func containsUnsafeCharacters(_ value: String) -> Bool {
    value.unicodeScalars.contains(where: isUnsafeCharacter)
  }
}

nonisolated extension TerminalLink {
  fileprivate static func fileDecision(for url: URL) -> Decision {
    guard url.isFileURL, url.query() == nil, url.fragment() == nil else {
      return .deny(.malformedURL)
    }
    if let host = url.host(), !host.isEmpty, host.caseInsensitiveCompare("localhost") != .orderedSame {
      return .deny(.malformedURL)
    }
    guard let canonicalURL = effectiveFileURL(url) else {
      return .deny(.inaccessibleFile)
    }
    let values: URLResourceValues
    do {
      values = try canonicalURL.resourceValues(forKeys: [
        .contentTypeKey,
        .isDirectoryKey,
        .isExecutableKey,
        .isRegularFileKey,
      ])
    } catch {
      return .deny(.inaccessibleFile)
    }
    guard values.isDirectory == true || values.isRegularFile == true else {
      return .deny(.inaccessibleFile)
    }
    guard !isUnsafeFile(canonicalURL, values: values) else {
      return .deny(.unsafeFile)
    }
    return .allow(canonicalURL)
  }

  fileprivate static func effectiveFileURL(_ url: URL) -> URL? {
    var current = url.standardizedFileURL.resolvingSymlinksInPath()
    for _ in 0..<8 {
      guard (try? current.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true else {
        return current
      }
      guard let target = try? URL(resolvingAliasFileAt: current, options: [.withoutUI, .withoutMounting]) else {
        return nil
      }
      current = target.standardizedFileURL.resolvingSymlinksInPath()
    }
    return nil
  }

  fileprivate static func isUnsafeFile(_ url: URL, values: URLResourceValues) -> Bool {
    if unsafePathExtensions.contains(url.pathExtension.lowercased()) {
      return true
    }
    if let type = values.contentType, unsafeContentTypes.contains(where: { type.conforms(to: $0) }) {
      return true
    }
    return values.isDirectory != true && values.isExecutable == true
  }

  fileprivate static func isUnsafeCharacter(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x00...0x1F, 0x7F...0x9F:
      true
    case 0x061C, 0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069:
      true
    case 0x2028...0x2029:
      true
    case 0x2060, 0xFEFF:
      true
    default:
      false
    }
  }

  fileprivate static let unsafePathExtensions: Set<String> = [
    "action",
    "app",
    "applescript",
    "class",
    "command",
    "desktop",
    "inetloc",
    "jar",
    "mobileconfig",
    "mpkg",
    "pkg",
    "scpt",
    "terminal",
    "tool",
    "url",
    "webloc",
    "workflow",
  ]

  fileprivate static let unsafeContentTypes: [UTType] = [
    .application,
    .executable,
    .script,
  ]
}
