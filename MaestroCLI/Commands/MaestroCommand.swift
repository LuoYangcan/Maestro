// MaestroCLI/Commands/MaestroCommand.swift
// Root command with bare path entry detection.

import ArgumentParser
import Foundation
import MaestroCLIShared

struct MaestroCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "maestro",
    abstract: "Control a running Maestro instance from the command line.",
    version: MaestroVersion.current,
    subcommands: [
      OpenCommand.self,
      ListCommand.self,
      FocusCommand.self,
      SendCommand.self,
      KeyCommand.self,
      ReadCommand.self,
    ],
    defaultSubcommand: OpenCommand.self
  )
}
