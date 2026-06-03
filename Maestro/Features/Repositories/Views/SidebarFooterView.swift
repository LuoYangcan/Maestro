import ComposableArchitecture
import SwiftUI

struct SidebarFooterView: View {
  let store: StoreOf<RepositoriesFeature>
  @Environment(\.surfaceBottomChromeBackgroundOpacity) private var surfaceBottomChromeBackgroundOpacity
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    HStack {
      Spacer()
      Button {
        withAnimation(.easeOut(duration: 0.18)) {
          _ = store.send(.activeAgents(.togglePanelVisibility))
        }
      } label: {
        Image(systemName: Self.activeAgentsPanelIconName(isPanelHidden: store.state.activeAgents.isPanelHidden))
          .accessibilityLabel(store.state.activeAgents.isPanelHidden ? "Show Active Agents" : "Hide Active Agents")
      }
      .help(
        AppShortcuts.helpText(
          title: store.state.activeAgents.isPanelHidden ? "Show Active Agents" : "Hide Active Agents",
          commandID: AppShortcuts.CommandID.toggleActiveAgentsPanel,
          in: resolvedKeybindings
        )
      )
      Button {
        store.send(.refreshWorktrees)
      } label: {
        Image(systemName: "arrow.clockwise")
          .symbolEffect(.rotate, options: .repeating, isActive: store.state.isRefreshingWorktrees)
          .accessibilityLabel("Refresh Worktrees")
      }
      .help(
        AppShortcuts.helpText(
          title: "Refresh Worktrees",
          commandID: AppShortcuts.CommandID.refreshWorktrees,
          in: resolvedKeybindings
        )
      )
      .disabled(store.state.repositoryRoots.isEmpty && !store.state.isRefreshingWorktrees)
      Button {
        store.send(.selectArchivedWorktrees)
      } label: {
        Image(systemName: "archivebox")
          .accessibilityLabel("Archived Worktrees")
      }
      .help(
        AppShortcuts.helpText(
          title: "Archived Worktrees",
          commandID: AppShortcuts.CommandID.archivedWorktrees,
          in: resolvedKeybindings
        ))
      Button("Settings", systemImage: "gearshape") {
        SettingsWindowManager.shared.show()
      }
      .labelStyle(.iconOnly)
      .help(
        AppShortcuts.helpText(
          title: "Settings",
          commandID: AppShortcuts.CommandID.openSettings,
          in: resolvedKeybindings
        ))
    }
    .buttonStyle(.plain)
    .font(.callout)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  static func activeAgentsPanelIconName(isPanelHidden: Bool) -> String {
    isPanelHidden ? "person.crop.rectangle.stack" : "person.crop.rectangle.stack.fill"
  }
}
