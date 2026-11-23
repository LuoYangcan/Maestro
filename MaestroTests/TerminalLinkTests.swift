import Foundation
import Testing

@testable import Maestro

struct TerminalLinkTests {
  @Test func allowsWebAndMailtoURLs() throws {
    let httpsURL = try #require(URL(string: "https://example.com/docs"))
    #expect(TerminalLink("https://example.com/docs").decision == .allow(httpsURL))

    let mailtoURL = try #require(URL(string: "mailto:hello@example.com"))
    #expect(TerminalLink("mailto:hello@example.com").decision == .allow(mailtoURL))
  }

  @Test func confirmsCustomSchemes() throws {
    let customURL = try #require(URL(string: "vscode://file/tmp/a.swift"))
    #expect(TerminalLink("vscode://file/tmp/a.swift").decision == .confirm(customURL))
  }

  @Test func deniesMalformedAndUnsafeTargets() {
    #expect(TerminalLink("").decision == .deny(.malformedURL))
    #expect(TerminalLink("https:relative").decision == .deny(.invalidWebURL))
    #expect(TerminalLink("mailto:").decision == .deny(.malformedURL))
    #expect(TerminalLink("https://example.com/\nfoo").decision == .deny(.unsafeCharacters))
    #expect(TerminalLink("https://example.com/\u{202E}evil").decision == .deny(.unsafeCharacters))
  }

  @Test func allowsPlainLocalFileAndDeniesExecutableFile() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-terminal-link-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let plainFile = directory.appendingPathComponent("notes.txt")
    try Data("hello".utf8).write(to: plainFile)
    let plainLink = TerminalLink(unknownKindValue: plainFile.path)
    #expect(plainLink.decision == .allow(plainFile.standardizedFileURL.resolvingSymlinksInPath()))

    let scriptFile = directory.appendingPathComponent("run.command")
    try Data("#!/bin/sh\necho hi\n".utf8).write(to: scriptFile)
    let scriptLink = TerminalLink(unknownKindValue: scriptFile.path)
    #expect(scriptLink.decision == .deny(.unsafeFile))
  }
}
