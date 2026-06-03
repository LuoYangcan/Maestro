import Foundation
import Testing

@testable import Maestro

@MainActor
struct CLIFocusCommandHandlerTests {
  private static let paneID = UUID(uuidString: "6E1A2A10-D99F-4E3F-920C-D93AA3C05764")!
  private static let tabID = UUID(uuidString: "2FC00CF0-3974-4E1B-BEF8-7A08A8E3B7C0")!

  private static func makeTarget(
    tabSelected: Bool = true,
    paneFocused: Bool = true
  ) -> FocusResolvedTarget {
    FocusResolvedTarget(
      worktreeID: "Maestro:/Users/onevcat/Projects/Maestro",
      worktreeName: "Maestro",
      worktreePath: "/Users/onevcat/Projects/Maestro",
      worktreeRootPath: "/Users/onevcat/Projects/Maestro",
      worktreeKind: .git,
      tabID: tabID,
      tabTitle: "Maestro 1",
      tabSelected: tabSelected,
      paneID: paneID,
      paneTitle: "zsh",
      paneCWD: "/Users/onevcat/Projects/Maestro",
      paneFocused: paneFocused
    )
  }

  @Test func successfulFocusReturnsSchemaConformantPayload() throws {
    var focusedTarget: FocusResolvedTarget?
    let handler = FocusCommandHandler(
      resolveProvider: { selector in
        switch selector {
        case .pane(let paneID):
          #expect(paneID == Self.paneID.uuidString)
          return .success(Self.makeTarget(tabSelected: false, paneFocused: false))
        case .none:
          return .success(Self.makeTarget(tabSelected: true, paneFocused: true))
        default:
          Issue.record("Unexpected selector: \(selector)")
          return .failure(.notFound("Unexpected selector"))
        }
      },
      focusPerformer: { target in
        focusedTarget = target
        return true
      },
      bringToFront: { true }
    )

    let response = handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .focus(FocusInput(selector: .pane(Self.paneID.uuidString)))
      )
    )

    #expect(response.ok)
    #expect(response.command == "focus")
    #expect(response.schemaVersion == "maestro.cli.focus.v1")
    #expect(focusedTarget?.paneID == Self.paneID)

    let payload = try #require(try response.data?.decode(as: FocusCommandPayload.self))
    #expect(payload.requested.selector == .pane)
    #expect(payload.requested.value == Self.paneID.uuidString)
    #expect(payload.resolvedVia == .pane)
    #expect(payload.broughtToFront == true)
    #expect(payload.target.worktree.id == "Maestro:/Users/onevcat/Projects/Maestro")
    #expect(payload.target.tab.id == Self.tabID.uuidString)
    #expect(payload.target.tab.selected == true)
    #expect(payload.target.pane.id == Self.paneID.uuidString)
    #expect(payload.target.pane.focused == true)
  }

  @Test func currentSelectorUsesNilRequestedValue() throws {
    var resolveNoneCount = 0
    let handler = FocusCommandHandler(
      resolveProvider: { selector in
        #expect(selector == .none)
        resolveNoneCount += 1
        if resolveNoneCount == 1 {
          return .success(Self.makeTarget(tabSelected: false, paneFocused: false))
        }
        return .success(Self.makeTarget(tabSelected: true, paneFocused: true))
      },
      focusPerformer: { _ in true },
      bringToFront: { true }
    )

    let response = handler.handle(
      envelope: CommandEnvelope(output: .json, command: .focus(FocusInput(selector: .none)))
    )

    #expect(response.ok)
    #expect(resolveNoneCount == 2)
    let payload = try #require(try response.data?.decode(as: FocusCommandPayload.self))
    #expect(payload.requested.selector == .current)
    #expect(payload.requested.value == nil)
    #expect(payload.resolvedVia == .pane)
  }

  @Test func autoSelectorWithTabUUIDResolvesViaTab() throws {
    var resolveNoneCount = 0
    let handler = FocusCommandHandler(
      resolveProvider: { selector in
        switch selector {
        case .auto(let value):
          #expect(value == Self.tabID.uuidString)
          return .success(Self.makeTarget(tabSelected: true, paneFocused: true))
        case .none:
          resolveNoneCount += 1
          return .success(Self.makeTarget(tabSelected: true, paneFocused: true))
        default:
          return .failure(.notFound("Unexpected selector"))
        }
      },
      focusPerformer: { _ in true },
      bringToFront: { true }
    )

    let response = handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .focus(FocusInput(selector: .auto(Self.tabID.uuidString)))
      )
    )

    #expect(response.ok)
    #expect(resolveNoneCount == 1)
    let payload = try #require(try response.data?.decode(as: FocusCommandPayload.self))
    #expect(payload.requested.selector == .auto)
    #expect(payload.requested.value == Self.tabID.uuidString)
    #expect(payload.resolvedVia == .tab)
  }

  @Test func autoSelectorWithWorktreeNameResolvesViaWorktree() throws {
    var resolveNoneCount = 0
    let handler = FocusCommandHandler(
      resolveProvider: { selector in
        switch selector {
        case .auto(let value):
          #expect(value == "Maestro")
          return .success(Self.makeTarget(tabSelected: true, paneFocused: true))
        case .none:
          resolveNoneCount += 1
          return .success(Self.makeTarget(tabSelected: true, paneFocused: true))
        default:
          return .failure(.notFound("Unexpected selector"))
        }
      },
      focusPerformer: { _ in true },
      bringToFront: { true }
    )

    let response = handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .focus(FocusInput(selector: .auto("Maestro")))
      )
    )

    #expect(response.ok)
    #expect(resolveNoneCount == 1)
    let payload = try #require(try response.data?.decode(as: FocusCommandPayload.self))
    #expect(payload.requested.selector == .auto)
    #expect(payload.requested.value == "Maestro")
    #expect(payload.resolvedVia == .worktree)
  }

  @Test func targetNotFoundMapsToContractCode() {
    let handler = FocusCommandHandler(
      resolveProvider: { _ in .failure(.notFound("Pane missing")) },
      focusPerformer: { _ in true },
      bringToFront: { true }
    )

    let response = handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .focus(FocusInput(selector: .pane("missing")))
      )
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.targetNotFound)
  }

  @Test func targetNotUniqueMapsToContractCode() {
    let handler = FocusCommandHandler(
      resolveProvider: { _ in .failure(.notUnique("Ambiguous worktree")) },
      focusPerformer: { _ in true },
      bringToFront: { true }
    )

    let response = handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .focus(FocusInput(selector: .worktree("Maestro")))
      )
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.targetNotUnique)
  }

  @Test func focusFailureReturnsFocusFailedCode() {
    let handler = FocusCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      focusPerformer: { _ in false },
      bringToFront: { true }
    )

    let response = handler.handle(
      envelope: CommandEnvelope(output: .json, command: .focus(FocusInput(selector: .none)))
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.focusFailed)
  }

  @Test func bringToFrontFailureReturnsFocusFailedCode() {
    let handler = FocusCommandHandler(
      resolveProvider: { _ in .success(Self.makeTarget()) },
      focusPerformer: { _ in true },
      bringToFront: { false }
    )

    let response = handler.handle(
      envelope: CommandEnvelope(output: .json, command: .focus(FocusInput(selector: .none)))
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.focusFailed)
  }

  @Test func finalTargetMustBeActiveOrFocusFails() {
    var resolveNoneCount = 0
    let handler = FocusCommandHandler(
      resolveProvider: { selector in
        switch selector {
        case .none:
          resolveNoneCount += 1
          if resolveNoneCount == 1 {
            return .success(Self.makeTarget(tabSelected: true, paneFocused: true))
          }
          return .success(Self.makeTarget(tabSelected: false, paneFocused: false))
        default:
          return .failure(.notFound("Unexpected selector"))
        }
      },
      focusPerformer: { _ in true },
      bringToFront: { true }
    )

    let response = handler.handle(
      envelope: CommandEnvelope(output: .json, command: .focus(FocusInput(selector: .none)))
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.focusFailed)
  }
}
