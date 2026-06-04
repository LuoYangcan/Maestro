import AppKit
import ComposableArchitecture
import Sharing
import SwiftUI

/// Content hosted in the Active Agents menu bar `NSPopover` (via `NSHostingController`).
/// Lists every active agent using the shared `ActiveAgentRow`; tapping a row surfaces the
/// main window (it may be hidden when driven from the menu bar) then reuses the existing
/// `entryTapped` action for focus.
struct ActiveAgentsMenuBarContent: View {
  @Bindable var store: StoreOf<AppFeature>
  let terminalManager: WorktreeTerminalManager
  @Shared(.repositoryAppearances) private var repositoryAppearances

  private let maxVisibleRows = 8

  var body: some View {
    let entries = store.repositories.activeAgents.entries
    let metadata = ActiveAgentRowDisplayResolver.worktreeMetadata(
      repositories: store.repositories.repositories,
      customTitles: store.repositories.repositoryCustomTitles,
      repositoryAppearances: repositoryAppearances
    )
    let rowDisplays = ActiveAgentRowDisplayResolver.displays(
      entries: entries,
      repositories: store.repositories.repositories,
      metadata: metadata
    )
    let selectedSurfaceID = selectedSurfaceID

    VStack(spacing: 0) {
      if entries.isEmpty {
        Text("New agents will appear here")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(entries) { entry in
              Button {
                NSApplication.shared.surfaceMainWindow()
                store.send(.repositories(.activeAgents(.entryTapped(entry.id))))
              } label: {
                ActiveAgentRow(
                  entry: entry,
                  titleName: rowDisplays[entry.id]?.titleName ?? entry.worktreeName,
                  branchName: rowDisplays[entry.id]?.branchName ?? entry.worktreeName,
                  repositoryColor: rowDisplays[entry.id]?.color,
                  isDimmed: selectedSurfaceID.map { entry.surfaceID != $0 } ?? false
                )
              }
              .buttonStyle(.plain)
              .help(helpText(for: entry))
            }
          }
          .padding(8)
        }
        .scrollIndicators(.never)
      }
    }
    .frame(width: 340, height: popoverHeight(entryCount: entries.count))
  }

  private var selectedSurfaceID: UUID? {
    store.repositories.selectedWorktreeID.flatMap { worktreeID in
      terminalManager.stateIfExists(for: worktreeID)?.activeSurfaceID
    }
  }

  private func popoverHeight(entryCount: Int) -> CGFloat {
    let visibleRows = min(maxVisibleRows, max(entryCount, 1))
    return CGFloat(visibleRows) * 48 + 16
  }

  private func helpText(for entry: ActiveAgentEntry) -> String {
    let trimmed = entry.tabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled tab" : trimmed
  }
}
