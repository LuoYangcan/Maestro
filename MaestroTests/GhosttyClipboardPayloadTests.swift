import AppKit
import GhosttyKit
import Testing

@testable import Maestro

@MainActor
struct GhosttyClipboardPayloadTests {
  private func makePasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    return pasteboard
  }

  @Test func readsPlainTextAndListsDeclaredMimes() {
    let pasteboard = makePasteboard()
    pasteboard.setString("hello", forType: .string)

    let payload = GhosttyClipboardPayload(pasteboard: pasteboard, mimes: ["text/plain"], list: true)

    #expect(payload.contents == [GhosttyClipboardContent(mime: "text/plain", data: Data("hello".utf8))])
    #expect(payload.available.contains("text/plain"))
    #expect(payload.hasText)
  }

  @Test func escapesFileURLsAsPlainText() {
    let pasteboard = makePasteboard()
    pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/my dir/file.txt") as NSURL])

    let payload = GhosttyClipboardPayload(pasteboard: pasteboard, mimes: ["text/plain"], list: true)

    #expect(payload.contents.map(\.mime) == ["text/plain"])
    #expect(payload.contents.first.flatMap { String(bytes: $0.data, encoding: .utf8) } == "/tmp/my\\ dir/file.txt")
    #expect(payload.available.first == "text/plain")
  }

  @Test func skipsUnavailableMimeTypes() {
    let pasteboard = makePasteboard()
    pasteboard.setString("x", forType: .string)

    let payload = GhosttyClipboardPayload(
      pasteboard: pasteboard,
      mimes: ["application/x-maestro-unknown", "image/png"],
      list: false
    )

    #expect(payload.contents.isEmpty)
    #expect(payload.available.isEmpty)
    #expect(!payload.hasText)
  }

  @Test func copiesConfirmationPayloadOutOfBorrowedMemory() {
    let text = "pasted"
    let mime = strdup("text/plain")!
    defer { free(mime) }

    let payload: GhosttyClipboardPayload = text.withCString { data in
      var content = ghostty_clipboard_content_s(mime: mime, data: data, len: text.utf8.count)
      return withUnsafePointer(to: &content) { contents in
        let names: [UnsafePointer<CChar>?] = [UnsafePointer(mime)]
        return names.withUnsafeBufferPointer { available in
          let confirm = ghostty_clipboard_confirm_s(
            contents: contents,
            contents_len: 1,
            available: available.baseAddress,
            available_len: 1,
            name: nil,
            can_remember: false
          )
          return GhosttyClipboardPayload(confirm: confirm)
        }
      }
    }

    #expect(payload.contents == [GhosttyClipboardContent(mime: "text/plain", data: Data(text.utf8))])
    #expect(payload.available == ["text/plain"])
    #expect(payload.hasText)
  }
}
