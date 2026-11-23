import Foundation

func identifyAgent(processName: String) -> DetectedAgent? {
  switch processName.lowercased() {
  case "pi":
    return .pi
  case "claude", "claude-code":
    return .claude
  case "codex", "omx", "oh-my-codex":
    return .codex
  case "gemini":
    return .gemini
  case "cursor", "cursor-agent":
    return .cursor
  case "cline":
    return .cline
  case "opencode", "open-code":
    return .opencode
  case "copilot", "github-copilot", "ghcs":
    return .copilot
  case "kimi", "kimi code":
    return .kimi
  case "droid":
    return .droid
  case "amp", "amp-local":
    return .amp
  // Bare `antigravity` stays unmapped: the desktop IDE ships a same-named launcher.
  case "agy", "antigravity-cli", "antigravity_cli":
    return .antigravity
  default:
    return nil
  }
}

struct IdentifiedAgentProcess: Equatable, Sendable {
  let agent: DetectedAgent
  let name: String
  let pid: pid_t
}

func identifyAgentInJob(_ job: ForegroundJob) -> IdentifiedAgentProcess? {
  var best: AgentCandidate?

  for process in job.processes {
    for candidate in agentCandidates(for: process) {
      guard let agent = identifyAgent(candidate: candidate, process: process) else { continue }
      if best == nil || candidate.score > best!.score {
        best = AgentCandidate(score: candidate.score, agent: agent, name: candidate.name, pid: process.pid)
      }
    }
  }

  return best.map { IdentifiedAgentProcess(agent: $0.agent, name: $0.name, pid: $0.pid) }
}

private let weakCandidateScore = 40

private func agentCandidates(for process: ForegroundProcess) -> [(name: String, score: Int)] {
  var candidates: [(String, Int)] = []
  let arguments =
    process.arguments
    ?? process.cmdline?.split(whereSeparator: \.isWhitespace).map(String.init)
    ?? []
  // `agy` spawns a transient `--bg-updater` child in the same foreground job.
  // Demote it below the TUI so enumeration order never selects the updater.
  let isAntigravityUpdater =
    arguments.dropFirst().first == "--bg-updater"
    || arguments.dropFirst().first == "-bg-updater"

  if let argv0 = process.argv0, let name = normalizedProcessName(argv0) {
    let demoted = isAntigravityUpdater && namesAntigravityCLI(name, process: process)
    candidates.append((name, demoted ? 60 : 80))
  }
  if let name = normalizedProcessName(process.name) {
    let demoted = isAntigravityUpdater && namesAntigravityCLI(name, process: process)
    candidates.append((name, demoted ? 50 : 70))
  }

  let primaryName = normalizedProcessName(process.argv0 ?? process.name) ?? process.name.lowercased()
  if isWrappedRuntime(primaryName), let cmdline = process.cmdline {
    for token in cmdline.split(whereSeparator: \.isWhitespace) {
      guard let name = normalizedProcessName(String(token)) else { continue }
      candidates.append((name, weakCandidateScore))
    }
  }

  return candidates
}

private func identifyAgent(candidate: (name: String, score: Int), process: ForegroundProcess) -> DetectedAgent? {
  if candidate.name == "agent", isCursorAgentAlias(process) {
    return .cursor
  }
  if candidate.score == weakCandidateScore,
    ["agy", "antigravity", "antigravity-cli", "antigravity_cli"].contains(candidate.name)
  {
    return nil
  }
  if candidate.name == "antigravity", isAntigravityCLIInstall(process) {
    return .antigravity
  }
  return identifyAgent(processName: candidate.name)
}

private func namesAntigravityCLI(_ name: String, process: ForegroundProcess) -> Bool {
  identifyAgent(processName: name) == .antigravity
    || (name == "antigravity" && isAntigravityCLIInstall(process))
}

// The Homebrew `antigravity-cli` cask execs `<Caskroom>/antigravity-cli/<ver>/antigravity`,
// so argv0/comm are bare `antigravity` (shared with the IDE launcher). Match only when the
// executable path itself lives under an `antigravity-cli` directory.
private func isAntigravityCLIInstall(_ process: ForegroundProcess) -> Bool {
  let executablePath =
    process.arguments?.first
    ?? process.cmdline?.split(whereSeparator: \.isWhitespace).first.map(String.init)
  guard let executablePath else { return false }
  let components = executablePath.lowercased().split(separator: "/")
  guard components.count > 1, components.last == "antigravity" else { return false }
  return components.dropLast().contains("antigravity-cli")
}

private func isCursorAgentAlias(_ process: ForegroundProcess) -> Bool {
  let haystack = [
    process.argv0,
    process.cmdline,
  ]
  .compactMap(\.self)
  .joined(separator: " ")
  .lowercased()

  return haystack.contains("cursor-agent")
    || haystack.contains("cursor.app")
}

private struct AgentCandidate {
  let score: Int
  let agent: DetectedAgent
  let name: String
  let pid: pid_t
}

private func normalizedProcessName(_ raw: String) -> String? {
  guard let basename = ProcessDetection.basename(raw) else { return nil }
  let lower = basename.lowercased()
  if lower.hasSuffix(".js") {
    return String(lower.dropLast(3))
  }
  return lower
}

private func isWrappedRuntime(_ name: String) -> Bool {
  [
    "node", "bun", "python", "python3", "ruby", "deno",
    "sh", "bash", "zsh", "fish", "tmux", "npx", "bunx",
  ].contains(name)
}
