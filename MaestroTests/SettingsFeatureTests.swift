import ComposableArchitecture
import CustomDump
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import Maestro

@MainActor
struct SettingsFeatureTests {
  @Test(.dependencies) func loadSettings() async {
    let loaded = GlobalSettings(
      appearanceMode: .dark,
      defaultEditorID: OpenWorktreeAction.automaticSettingsID,
      confirmBeforeQuit: true,
      updateChannel: .stable,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: true,
      inAppNotificationsEnabled: false,
      notificationSoundEnabled: true,
      systemNotificationsEnabled: true,
      moveNotifiedWorktreeToTop: false,
      githubIntegrationEnabled: true,
      deleteBranchOnDeleteWorktree: false,
      mergedWorktreeAction: .archive,
      promptForWorktreeCreation: true
    )
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = loaded }

    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    await store.send(.task)
    await store.receive(\.settingsLoaded) {
      $0.appearanceMode = .dark
      $0.defaultEditorID = OpenWorktreeAction.automaticSettingsID
      $0.confirmBeforeQuit = true
      $0.updateChannel = .stable
      $0.updatesAutomaticallyCheckForUpdates = false
      $0.updatesAutomaticallyDownloadUpdates = true
      $0.inAppNotificationsEnabled = false
      $0.notificationSoundEnabled = true
      $0.moveNotifiedWorktreeToTop = false
      $0.systemNotificationsEnabled = true
      $0.githubIntegrationEnabled = true
      $0.deleteBranchOnDeleteWorktree = false
      $0.mergedWorktreeAction = .archive
      $0.promptForWorktreeCreation = true
    }
    await store.receive(\.delegate.settingsChanged)
  }

  @Test(.dependencies) func savesUpdatesChanges() async {
    let initialSettings = GlobalSettings(
      appearanceMode: .system,
      defaultEditorID: OpenWorktreeAction.automaticSettingsID,
      confirmBeforeQuit: true,
      updateChannel: .stable,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: false,
      inAppNotificationsEnabled: false,
      notificationSoundEnabled: false,
      systemNotificationsEnabled: false,
      moveNotifiedWorktreeToTop: true,
      githubIntegrationEnabled: true,
      deleteBranchOnDeleteWorktree: true,
      mergedWorktreeAction: nil,
      promptForWorktreeCreation: false
    )
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.binding(.set(\.appearanceMode, .light))) {
      $0.appearanceMode = .light
    }
    let expectedSettings = GlobalSettings(
      appearanceMode: .light,
      defaultEditorID: initialSettings.defaultEditorID,
      confirmBeforeQuit: initialSettings.confirmBeforeQuit,
      updateChannel: initialSettings.updateChannel,
      updatesAutomaticallyCheckForUpdates: initialSettings.updatesAutomaticallyCheckForUpdates,
      updatesAutomaticallyDownloadUpdates: initialSettings.updatesAutomaticallyDownloadUpdates,
      inAppNotificationsEnabled: initialSettings.inAppNotificationsEnabled,
      notificationSoundEnabled: initialSettings.notificationSoundEnabled,
      systemNotificationsEnabled: initialSettings.systemNotificationsEnabled,
      moveNotifiedWorktreeToTop: initialSettings.moveNotifiedWorktreeToTop,
      githubIntegrationEnabled: initialSettings.githubIntegrationEnabled,
      deleteBranchOnDeleteWorktree: initialSettings.deleteBranchOnDeleteWorktree,
      mergedWorktreeAction: initialSettings.mergedWorktreeAction,
      promptForWorktreeCreation: initialSettings.promptForWorktreeCreation
    )
    await store.receive(\.delegate.settingsChanged)

    expectNoDifference(settingsFile.global, expectedSettings)
  }

  @Test(.dependencies) func setSystemNotificationsEnabledPersistsChanges() async {
    var initialSettings = GlobalSettings.default
    initialSettings.systemNotificationsEnabled = false
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.setSystemNotificationsEnabled(true)) {
      $0.systemNotificationsEnabled = true
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(settingsFile.global.systemNotificationsEnabled == true)
  }

  @Test(.dependencies) func refreshDockBadgeAuthorizationStoresSystemState() async {
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.systemNotificationClient.dockBadgeAuthorization = { .badgeDisabled }
    }

    await store.send(.refreshDockBadgeAuthorization)
    await store.receive(\.dockBadgeAuthorizationResponse) {
      $0.dockBadgeAuthorization = .badgeDisabled
    }
  }

  @Test(.dependencies) func selectionDoesNotMutateRepositorySettings() async {
    let selection = SettingsSection.repository("repo-id")
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    await store.send(.setSelection(selection)) {
      $0.selection = selection
    }

    await store.send(.setSelection(.general)) {
      $0.selection = .general
    }
  }

  @Test(.dependencies) func loadingSettingsDoesNotResetSelection() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let selection = SettingsSection.repository("repo-id")
    var state = SettingsFeature.State()
    state.selection = selection
    state.repositorySettings = RepositorySettingsFeature.State(
      rootURL: rootURL,
      repositoryKind: .git,
      settings: .default,
      userSettings: .default
    )
    let store = TestStore(initialState: state) {
      SettingsFeature()
    }

    let loaded = GlobalSettings(
      appearanceMode: .light,
      defaultEditorID: OpenWorktreeAction.automaticSettingsID,
      confirmBeforeQuit: false,
      updateChannel: .tip,
      updatesAutomaticallyCheckForUpdates: false,
      updatesAutomaticallyDownloadUpdates: true,
      inAppNotificationsEnabled: false,
      notificationSoundEnabled: false,
      systemNotificationsEnabled: true,
      moveNotifiedWorktreeToTop: true,
      githubIntegrationEnabled: true,
      deleteBranchOnDeleteWorktree: true,
      mergedWorktreeAction: .archive,
      promptForWorktreeCreation: false
    )

    await store.send(.settingsLoaded(loaded)) {
      $0.appearanceMode = .light
      $0.defaultEditorID = OpenWorktreeAction.automaticSettingsID
      $0.confirmBeforeQuit = false
      $0.updateChannel = .tip
      $0.updatesAutomaticallyCheckForUpdates = false
      $0.updatesAutomaticallyDownloadUpdates = true
      $0.inAppNotificationsEnabled = false
      $0.notificationSoundEnabled = false
      $0.moveNotifiedWorktreeToTop = true
      $0.systemNotificationsEnabled = true
      $0.githubIntegrationEnabled = true
      $0.deleteBranchOnDeleteWorktree = true
      $0.mergedWorktreeAction = .archive
      $0.promptForWorktreeCreation = false
      $0.selection = selection
      $0.repositorySettings = RepositorySettingsFeature.State(
        rootURL: rootURL,
        repositoryKind: .git,
        settings: .default,
        userSettings: .default
      )
    }
    await store.receive(\.delegate.settingsChanged)
  }

  @Test(.dependencies) func settingsLoadedNormalizesDefaultWorktreeBaseDirectoryPath() async {
    var loaded = GlobalSettings.default
    loaded.defaultWorktreeBaseDirectoryPath = " ~/worktrees "
    let expectedPath = MaestroPaths.normalizedWorktreeBaseDirectoryPath(" ~/worktrees ")!
    let storage = SettingsTestStorage()
    let settingsFileURL = URL(fileURLWithPath: "/tmp/maestro-settings-\(UUID().uuidString).json")
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.settingsFileStorage = storage.storage
      $0.settingsFileURL = settingsFileURL
    }

    await store.send(.settingsLoaded(loaded)) {
      $0.defaultWorktreeBaseDirectoryPath = expectedPath
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(store.state.defaultWorktreeBaseDirectoryPath == expectedPath)
  }

  @Test(.dependencies) func changingDefaultWorktreeBaseDirectoryUpdatesRepositorySettingsState() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    let expectedPath = MaestroPaths.normalizedWorktreeBaseDirectoryPath(" ~/worktrees ")!
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = .default }
    var state = SettingsFeature.State()
    state.repositorySettings = RepositorySettingsFeature.State(
      rootURL: rootURL,
      repositoryKind: .git,
      settings: .default,
      userSettings: .default
    )
    let store = TestStore(initialState: state) {
      SettingsFeature()
    }

    await store.send(.binding(.set(\.defaultWorktreeBaseDirectoryPath, " ~/worktrees "))) {
      $0.defaultWorktreeBaseDirectoryPath = " ~/worktrees "
      $0.repositorySettings?.globalDefaultWorktreeBaseDirectoryPath = expectedPath
    }
    await store.receive(\.delegate.settingsChanged)
    #expect(store.state.repositorySettings?.globalDefaultWorktreeBaseDirectoryPath == expectedPath)
    #expect(settingsFile.global.defaultWorktreeBaseDirectoryPath == expectedPath)
  }

  @Test(.dependencies) func changingGlobalOverrideDefaultsUpdatesRepositorySettingsState() async {
    let rootURL = URL(fileURLWithPath: "/tmp/repo")
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = .default }
    var state = SettingsFeature.State()
    state.repositorySettings = RepositorySettingsFeature.State(
      rootURL: rootURL,
      repositoryKind: .git,
      settings: .default,
      userSettings: .default
    )
    let store = TestStore(initialState: state) {
      SettingsFeature()
    }

    await store.send(.binding(.set(\.copyIgnoredOnWorktreeCreate, true))) {
      $0.copyIgnoredOnWorktreeCreate = true
      $0.repositorySettings?.globalCopyIgnoredOnWorktreeCreate = true
    }
    await store.receive(\.delegate.settingsChanged)

    await store.send(.binding(.set(\.copyUntrackedOnWorktreeCreate, true))) {
      $0.copyUntrackedOnWorktreeCreate = true
      $0.repositorySettings?.globalCopyUntrackedOnWorktreeCreate = true
    }
    await store.receive(\.delegate.settingsChanged)

    await store.send(.binding(.set(\.pullRequestMergeStrategy, .squash))) {
      $0.pullRequestMergeStrategy = .squash
      $0.repositorySettings?.globalPullRequestMergeStrategy = .squash
    }
    await store.receive(\.delegate.settingsChanged)

    #expect(store.state.repositorySettings?.globalCopyIgnoredOnWorktreeCreate == true)
    #expect(store.state.repositorySettings?.globalCopyUntrackedOnWorktreeCreate == true)
    #expect(store.state.repositorySettings?.globalPullRequestMergeStrategy == .squash)
    #expect(settingsFile.global.copyIgnoredOnWorktreeCreate == true)
    #expect(settingsFile.global.copyUntrackedOnWorktreeCreate == true)
    #expect(settingsFile.global.pullRequestMergeStrategy == .squash)
  }

  @Test(.dependencies) func setTerminalFontSizePersistsWithoutGlobalFanout() async {
    var initialSettings = GlobalSettings.default
    initialSettings.terminalFontSize = nil
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.setTerminalFontSize(18)) {
      $0.terminalFontSize = 18
    }
    await store.receive(\.delegate.terminalFontSizeChanged)
    await store.finish()

    #expect(settingsFile.global.terminalFontSize == 18)
  }

  @Test(.dependencies) func setTerminalFontSizeIgnoresDuplicateValue() async {
    var initialSettings = GlobalSettings.default
    initialSettings.terminalFontSize = 18
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.setTerminalFontSize(18))
    await store.finish()

    #expect(settingsFile.global.terminalFontSize == 18)
  }

  @Test(.dependencies) func keybindingOverridesPersistAndFanOut() async {
    var initialSettings = GlobalSettings.default
    initialSettings.keybindingUserOverrides = .empty
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let overrides = KeybindingUserOverrideStore(
      overrides: [
        AppShortcuts.CommandID.openSettings: KeybindingUserOverride(
          binding: Keybinding(key: ";", modifiers: .init(command: true))
        )
      ]
    )

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.binding(.set(\.keybindingUserOverrides, overrides))) {
      $0.keybindingUserOverrides = overrides
    }
    await store.receive(\.delegate.settingsChanged)

    #expect(settingsFile.global.keybindingUserOverrides == overrides)
  }

  @Test(.dependencies) func autoShowActiveAgentsPanelPersistsChanges() async {
    var initialSettings = GlobalSettings.default
    initialSettings.autoShowActiveAgentsPanel = false
    @Shared(.settingsFile) var settingsFile
    $settingsFile.withLock { $0.global = initialSettings }

    let store = TestStore(initialState: SettingsFeature.State(settings: initialSettings)) {
      SettingsFeature()
    }

    await store.send(.binding(.set(\.autoShowActiveAgentsPanel, true))) {
      $0.autoShowActiveAgentsPanel = true
    }
    await store.receive(\.delegate.settingsChanged)

    #expect(settingsFile.global.autoShowActiveAgentsPanel == true)
  }

  @Test(.dependencies) func clearTerminalLayoutSnapshotSendsDelegate() async {
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.terminalLayoutPersistence.clearSnapshot = { true }
    }

    await store.send(.clearTerminalLayoutSnapshotButtonTapped)
    await store.receive(\.delegate.terminalLayoutSnapshotCleared)
  }
}
