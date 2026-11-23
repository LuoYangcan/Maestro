import Testing

@testable import Maestro

struct AgentClassifierTests {
  @Test func identifiesDirectAgentProcessNames() {
    #expect(identifyAgent(processName: "pi") == .pi)
    #expect(identifyAgent(processName: "claude") == .claude)
    #expect(identifyAgent(processName: "claude-code") == .claude)
    #expect(identifyAgent(processName: "codex") == .codex)
    #expect(identifyAgent(processName: "omx") == .codex)
    #expect(identifyAgent(processName: "oh-my-codex") == .codex)
    #expect(identifyAgent(processName: "gemini") == .gemini)
    #expect(identifyAgent(processName: "cursor") == .cursor)
    #expect(identifyAgent(processName: "cursor-agent") == .cursor)
    #expect(identifyAgent(processName: "cline") == .cline)
    #expect(identifyAgent(processName: "opencode") == .opencode)
    #expect(identifyAgent(processName: "open-code") == .opencode)
    #expect(identifyAgent(processName: "github-copilot") == .copilot)
    #expect(identifyAgent(processName: "ghcs") == .copilot)
    #expect(identifyAgent(processName: "kimi") == .kimi)
    #expect(identifyAgent(processName: "Kimi Code") == .kimi)
    #expect(identifyAgent(processName: "droid") == .droid)
    #expect(identifyAgent(processName: "amp") == .amp)
    #expect(identifyAgent(processName: "amp-local") == .amp)
    #expect(identifyAgent(processName: "agy") == .antigravity)
    #expect(identifyAgent(processName: "antigravity-cli") == .antigravity)
    #expect(identifyAgent(processName: "antigravity_cli") == .antigravity)
    #expect(identifyAgent(processName: "antigravity") == nil)
  }

  @Test func identifiesCursorAgentAliasCommandLines() throws {
    let job = ForegroundJob(
      processGroupID: 42,
      processes: [
        ForegroundProcess(
          pid: 100,
          name: "agent",
          argv0: "/Users/onevcat/.local/bin/agent",
          cmdline: """
            /Users/onevcat/.local/bin/agent --use-system-ca \
            /Users/onevcat/.local/share/cursor-agent/versions/2026.05.09-0afadcc/index.js
            """
        )
      ]
    )

    let result = try #require(identifyAgentInJob(job))
    #expect(result.agent == .cursor)
    #expect(result.name == "agent")
    #expect(result.pid == 100)
  }

  @Test func ignoresGenericAgentProcessWithoutCursorContext() {
    let job = ForegroundJob(
      processGroupID: 42,
      processes: [
        ForegroundProcess(
          pid: 100,
          name: "agent",
          argv0: "agent",
          cmdline: "agent --serve"
        )
      ]
    )

    #expect(identifyAgent(processName: "agent") == nil)
    #expect(identifyAgentInJob(job) == nil)
  }

  @Test func identifiesCursorAgentCommandLines() throws {
    let job = ForegroundJob(
      processGroupID: 42,
      processes: [
        ForegroundProcess(
          pid: 100,
          name: "node",
          argv0: "node",
          cmdline: "node /opt/homebrew/bin/cursor-agent"
        )
      ]
    )

    let result = try #require(identifyAgentInJob(job))
    #expect(result.agent == .cursor)
    #expect(result.name == "cursor-agent")
    #expect(result.pid == 100)
  }

  @Test func ignoresPlainShellsAndUnknownProcesses() {
    #expect(identifyAgent(processName: "zsh") == nil)
    #expect(identifyAgent(processName: "bash") == nil)
    #expect(identifyAgent(processName: "node") == nil)
    #expect(identifyAgent(processName: "vim") == nil)
  }

  @Test func identifiesWrappedRuntimeCommandLines() throws {
    let job = ForegroundJob(
      processGroupID: 42,
      processes: [
        ForegroundProcess(
          pid: 100,
          name: "node",
          argv0: "node",
          cmdline: "node /opt/homebrew/bin/codex --model gpt-5"
        )
      ]
    )

    let result = try #require(identifyAgentInJob(job))
    #expect(result.agent == .codex)
    #expect(result.name == "codex")
    #expect(result.pid == 100)
  }

  @Test func identifiesOmxAsCodexWrapper() throws {
    let job = ForegroundJob(
      processGroupID: 42,
      processes: [
        ForegroundProcess(
          pid: 100,
          name: "node",
          argv0: "node",
          cmdline: "node /opt/homebrew/bin/omx --madmax --high"
        )
      ]
    )

    let result = try #require(identifyAgentInJob(job))
    #expect(result.agent == .codex)
    #expect(result.name == "omx")
    #expect(result.pid == 100)
  }

  @Test func prefersDirectAgentProcessOverWrapper() throws {
    let job = ForegroundJob(
      processGroupID: 42,
      processes: [
        ForegroundProcess(pid: 100, name: "node", argv0: "node", cmdline: "node /tmp/codex"),
        ForegroundProcess(pid: 101, name: "claude", argv0: "claude", cmdline: "claude"),
      ]
    )

    let result = try #require(identifyAgentInJob(job))
    #expect(result.agent == .claude)
    #expect(result.name == "claude")
    #expect(result.pid == 101)
  }

  @Test func demotesAntigravityBackgroundUpdaterBelowInteractiveTUI() throws {
    let tui = ForegroundProcess(
      pid: 200,
      name: "agy",
      argv0: "agy",
      cmdline: "agy --resume",
      arguments: ["agy", "--resume"]
    )
    let updater = ForegroundProcess(
      pid: 201,
      name: "agy",
      argv0: "agy",
      cmdline: "agy --bg-updater --app_data_dir=antigravity-cli",
      arguments: ["agy", "--bg-updater", "--app_data_dir=antigravity-cli"]
    )
    let singleDashUpdater = ForegroundProcess(
      pid: 202,
      name: "agy",
      argv0: "agy",
      cmdline: "agy -bg-updater --app_data_dir=antigravity-cli",
      arguments: ["agy", "-bg-updater", "--app_data_dir=antigravity-cli"]
    )

    for processes in [[tui, updater], [updater, tui], [tui, singleDashUpdater], [singleDashUpdater, tui]] {
      let identified = try #require(identifyAgentInJob(ForegroundJob(processGroupID: 200, processes: processes)))
      #expect(identified.agent == .antigravity)
      #expect(identified.pid == 200)
    }

    let nameOnlyTUI = ForegroundProcess(pid: 205, name: "agy", argv0: nil, cmdline: nil)
    let nameOnlyUpdater = ForegroundProcess(pid: 206, name: "agy", argv0: nil, cmdline: "agy --bg-updater")
    for processes in [[nameOnlyTUI, nameOnlyUpdater], [nameOnlyUpdater, nameOnlyTUI]] {
      let identified = try #require(identifyAgentInJob(ForegroundJob(processGroupID: 205, processes: processes)))
      #expect(identified.agent == .antigravity)
      #expect(identified.pid == 205)
    }
  }

  @Test func recognizesHomebrewAntigravityCLIInstallPathAndRejectsBareOrWrapped() throws {
    let caskPath = "/opt/homebrew/Caskroom/antigravity-cli/1.5.9,4515810895593472/antigravity"
    let cask = ForegroundProcess(
      pid: 300,
      name: "antigravity",
      argv0: "antigravity",
      cmdline: caskPath,
      arguments: [caskPath]
    )
    let caskUpdater = ForegroundProcess(
      pid: 301,
      name: "antigravity",
      argv0: "antigravity",
      cmdline: "\(caskPath) --bg-updater",
      arguments: [caskPath, "--bg-updater"]
    )
    for processes in [[cask, caskUpdater], [caskUpdater, cask]] {
      let identified = try #require(identifyAgentInJob(ForegroundJob(processGroupID: 300, processes: processes)))
      #expect(identified.agent == .antigravity)
      #expect(identified.pid == 300)
    }

    let spacedPath = "/Users/me/My Tools/antigravity-cli/antigravity"
    let spaced = ForegroundProcess(
      pid: 302,
      name: "antigravity",
      argv0: "antigravity",
      cmdline: "\(spacedPath) --resume",
      arguments: [spacedPath, "--resume"]
    )
    #expect(identifyAgentInJob(ForegroundJob(processGroupID: 302, processes: [spaced]))?.agent == .antigravity)

    let rejected: [ForegroundProcess] = [
      ForegroundProcess(
        pid: 310,
        name: "antigravity",
        argv0: "antigravity",
        cmdline: "/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity --wait",
        arguments: ["/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity", "--wait"]
      ),
      ForegroundProcess(pid: 311, name: "antigravity", argv0: "antigravity", cmdline: "antigravity"),
      ForegroundProcess(pid: 312, name: "node", argv0: "node", cmdline: "node /tmp/app.js --model agy"),
      ForegroundProcess(
        pid: 313,
        name: "bash",
        argv0: "bash",
        cmdline: "bash -c /opt/homebrew/Caskroom/antigravity-cli/1.5.9/antigravity",
        arguments: ["bash", "-c", "/opt/homebrew/Caskroom/antigravity-cli/1.5.9/antigravity"]
      ),
    ]
    for process in rejected {
      #expect(identifyAgentInJob(ForegroundJob(processGroupID: process.pid, processes: [process])) == nil)
    }
  }
}
