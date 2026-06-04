import AppKit
import ComposableArchitecture
import SwiftUI

/// Owns the Active Agents `NSStatusItem` in the system menu bar.
///
/// SwiftUI `MenuBarExtra` projects its label down onto `NSStatusItem.button`'s only
/// two native slots — a single image and a single title — so a second status symbol
/// `Image` is silently dropped. Driving `NSStatusItem` directly sidesteps that: the cat
/// occupies the image slot, while a vertical traffic-light of status dots (red on top for
/// blocked, green on the bottom for done) lives in the `attributedTitle` as a self-drawn
/// `NSTextAttachment` image. Both dots can light at once; the title is empty when nothing
/// is blocked or done, leaving just the cat. A text attachment lays out a single inline
/// image, so the two stacked dots are baked into one image rather than two attachments.
@MainActor
@Observable
final class ActiveAgentsStatusItemController {
  private let statusItem: NSStatusItem
  private let popover = NSPopover()
  private let store: StoreOf<AppFeature>

  init(store: StoreOf<AppFeature>, terminalManager: WorktreeTerminalManager) {
    self.store = store
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    let cat = NSImage(named: "MenuBarConductorCat")
    cat?.isTemplate = true
    if let cat {
      // The cat artwork is wider than tall; lock height to the menu bar's ~16pt and
      // derive width from the intrinsic aspect ratio so it isn't squished to a square.
      let height: CGFloat = 16
      let aspect = cat.size.height > 0 ? cat.size.width / cat.size.height : 1
      cat.size = NSSize(width: (height * aspect).rounded(), height: height)
    }
    if let button = statusItem.button {
      button.image = cat
      button.imagePosition = .imageLeading
      button.target = self
      button.action = #selector(togglePopover)
      button.toolTip = "Active Agents"
    }

    popover.behavior = .transient
    popover.contentViewController = NSHostingController(
      rootView: ActiveAgentsMenuBarContent(store: store, terminalManager: terminalManager)
    )

    renderAndObserve()
  }

  isolated deinit {
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  /// Renders the current state, then arms a one-shot observation that re-invokes this method
  /// when any read `@ObservableState` property changes. `withObservationTracking`'s `onChange`
  /// fires once and outside the tracking scope, so we re-arm on every change to keep observing.
  private func renderAndObserve() {
    withObservationTracking {
      render()
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.renderAndObserve()
      }
    }
  }

  private func render() {
    guard let button = statusItem.button else { return }
    let entries = store.repositories.activeAgents.entries
    let hasBlocked = entries.contains { $0.displayState == .blocked }
    let hasDone = entries.contains { $0.displayState == .done }

    guard let dots = statusDots(hasBlocked: hasBlocked, hasDone: hasDone) else {
      button.attributedTitle = NSAttributedString(string: "")
      return
    }
    let attachment = NSTextAttachment()
    attachment.image = dots
    attachment.bounds = CGRect(x: 0, y: -4, width: dots.size.width, height: dots.size.height)
    let title = NSMutableAttributedString(string: " ")
    title.append(NSAttributedString(attachment: attachment))
    button.attributedTitle = title
  }

  /// Draws the status dots as a vertical traffic-light: a red dot in the top slot when any
  /// agent is blocked and a green dot in the bottom slot when any is done. Both can show at
  /// once; returns nil when neither applies so the title stays empty. The image is non-template
  /// so its colors survive the button's overall template rendering.
  private func statusDots(hasBlocked: Bool, hasDone: Bool) -> NSImage? {
    guard hasBlocked || hasDone else { return nil }

    let diameter: CGFloat = 5
    let gap: CGFloat = 2
    let size = NSSize(width: diameter, height: diameter * 2 + gap)
    let image = NSImage(size: size, flipped: false) { _ in
      if hasBlocked {
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: CGRect(x: 0, y: diameter + gap, width: diameter, height: diameter)).fill()
      }
      if hasDone {
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)).fill()
      }
      return true
    }
    image.isTemplate = false
    return image
  }

  @objc private func togglePopover() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }
}
