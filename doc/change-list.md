# Fork Change Log

## Upstream Baseline

| Key | Value |
| --- | --- |
| Commit | `5e88ec5dfc74af165781e8d5a41505867b23dc06` |
| Tag | post-v0.8.5 |
| Date | 2026-05-05 |

All upstream changes up to and including this commit have been reviewed.
Future upstream checks should only inspect commits **after** this baseline.

---

## 2026-06-04 — Rebrand to Maestro + fork divergence

### Fork-only changes

- **Rebrand supacode/Prowl → Maestro** (`5b2bb2e2`, `e6a14c5e`) — renamed app module dir `supacode/`→`Maestro/` and `supacodeTests/`→`MaestroTests/`, the CLI target `ProwlCLI`→`MaestroCLI` (binary `prowl`→`maestro`, `ProwlVersion`→`MaestroVersion`), the Xcode project `supacode.xcodeproj`→`Maestro.xcodeproj` and scheme to `Maestro` (`PRODUCT_NAME=Maestro`), Makefile recipes, SPM cache paths, and the embedded CLI resource dir `Resources/prowl-cli`→`maestro-cli`. Bundle ID, Application Support data dir, drag UTType, UserDefaults key, dispatch queue label, and log subsystem all switched to `com.yangcanluo.maestro`; Sparkle feed repointed at `LuoYangcan/Maestro`; Homebrew cask zap paths updated. App display name and Quit menu now read "Maestro".
- **Analytics/telemetry removed** (`5b2bb2e2`) — dropped PostHog and Sentry SPM packages; `AnalyticsClient.liveValue` is now no-ops; `AnalyticsContext` + `InstallIdentifier` deleted. `MemoryWatchdog` kept but rewired from analytics/Sentry to local `SupaLogger` logging. Makefile drops `PROWL_SENTRY_DSN` / `PROWL_POSTHOG_*` secrets.
- **Updates tab hidden, auto-update disabled** (`8db5dc10`) — removed the Updates tab from the Settings sidebar and defaulted `updatesAutomaticallyCheckForUpdates` to `false` so the fork does not background-check a non-existent appcast. The toolbar update button self-hides when no update is available.
- **Upstream distribution links removed** (`bcc3e0d9`) — dropped Homepage / Release Notes / Submit GitHub Issue links (onevcat / prowl.onev.cat) from the sidebar footer Help menu and the menu-bar Help command group.
- **Active agents surfaced in the system menu bar** (`7de6b191`, PR #10) — added an `NSStatusItem` (conductor-cat icon + stacked red/green blocked/done dots) and a popover listing running agents across worktrees, driving the `NSStatusItem` directly (MenuBarExtra's two-slot label limit forced going around SwiftUI).
- **Active agent directory/title accuracy fixes** (`bd9fcf26`, `5b4d9322`, `fbd717ae`, PR #4) — active-agent rows resolve their working directory from the agent process's actual cwd, refresh on directory changes, and show the worktree directory in the title so rows identify the correct worktree.
- **Docs consolidated into `doc/`** (`9bde569b`) — renamed `doc-onevcat/`→`doc/` and dropped ~3500 lines of transient upstream design docs / implementation plans, keeping CLI contracts, fork-sync/release docs, and this change list; updated references in `AGENTS.md`, skills, and `OpenCommandHandler`.
- **README rewritten + icon refresh** (`fa70d7de`, `1b6c462b`, `21607123`, `923b60b8`, `b090eff3`) — bilingual landing page (`README.md` + `README.en.md`) framed as a personal fork, dead onevcat download/marketing links removed, in-repo icon asset (`doc/maestro-icon.png`), schema `$id` moved off `maestro.onev.cat`, and the macOS app icon refreshed to the conductor-cat.

### Decisions

- **All dev/PRs stay in the personal fork** — PRs target `LuoYangcan/Maestro`, never upstream (`onevcat/Prowl` or `supabitapp/supacode`); the `block-upstream-pr` hook (introduced `9970560`, repointed at the renamed fork in `909738fe`) enforces this, and the "always submit a PR after an execplan" rule was removed (`d2638538`).
- **Auto-update stays off** until the fork ships its own appcast; the Sparkle wiring/reducer are retained but do not background-check by default.

---

## 2026-05-09 — Ghostty fork patch

- Created `onevcat/ghostty` fork branch `release/v1.3.1-patched` from upstream tag `v1.3.1`.
- Added fork-only embedded C API `ghostty_surface_pid(ghostty_surface_t)` for per-pane agent process detection.
- Maestro submodule now tracks the patched fork branch. Upgrade procedure is documented in
  `doc/fork-sync-ghostty.md`.

---

## 2026-05-08 — Review through post-v0.8.5

### Upstream changes reviewed

Reviewed 25 commits on `supabitapp/supacode` from `c4e9be3b` (v0.8.1, 2026-04-19) through
`5e88ec5d` (post-v0.8.5, 2026-05-05). Significant additions:

- **Ghostty key event routing** (`6c807c63`, #259; `539c0feb`, #264) — upstream fixed two
  `performKeyEquivalent` edge cases: only forward unmatched Ghostty bindings to a real main-menu item, and only
  consume keys from the actual first responder.
- **Repository and PR targeting** (`a4cdad9e`, #261) — resolves the GitHub PR owner/repo with `gh repo view`, which
  matters for fork clones whose remotes may point at different owners.
- **Notification, tab, focus, and window UX** (`072ad1e7`, #266; `6615f49c`, #269; `b34a66d5`, #279;
  `71dc4b57`, #295; `028ef412`, #297; `5e88ec5d`, #298) — upstream added jump-to-unread notifications,
  custom tab titles, worktree history, sidebar-to-terminal arrow focus, dynamic window titles, and main-window-only
  quit confirmation.
- **Sidebar/repository appearance and polish** (`4d19b068`, #260; `9bae228e`, #276; `3af3a164`, #258;
  `57e620a7`, #265; `514c3ceb`, #283) — dim inactive split panes, per-repo title/color, detail toolbar and loading
  state polish, sidebar animation CPU reductions, and script menu cache fixes.
- **Agent/editor/platform additions** (`943f3fab`, #245; `6fff0218`, #262; `650a6b52`, #292; `e06c07a0`) —
  Kiro and Pi agents, Android Studio editor support, and app icon bundle metadata.
- **Build/release housekeeping** (`92c7c461`, `644bd468`, `3b07571b`, `34da9417`, `bd9da925`, `4a8611d9`) —
  CI concurrency and upstream semantic version/build-number bumps.

### Decisions

- **Ported to Maestro PRs**: Ghostty key routing (#255), fork-aware PR repo resolution (#256), worktree history
  (#260), dynamic window title plus main-window quit behavior (#261), loading overlay polish (#262), sidebar animation
  CPU fix (#263), Android Studio editor support (#264), sidebar right-arrow focus (#265), test workflow concurrency
  (#266), and `CFBundleIconName` metadata (#267).
- **Reviewed and skipped**: Notifications UX (#266 upstream), inactive split dimming (#260 upstream), tab renaming
  (#269 upstream), and bare-repo detection (#263 upstream) were already covered, intentionally different, or not
  currently applicable in the fork.
- **Skipped due fork-specific architecture**: Repository title/color (#276 upstream) conflicts with Maestro's richer
  repository appearance model; Kiro/Pi agent hooks rely on upstream settings/hook modules not present in this fork;
  Run Script dropdown caching does not apply to Maestro's current popover/button implementation.
- **Skipped due fork release policy**: Upstream release-tip/warm-cache/inspect-dependencies workflow concurrency and
  semantic version bumps do not apply. Maestro keeps local, notarized, date-based releases.

---

## 2026-04-20 — Review through v0.8.1

### Upstream changes reviewed

Reviewed 47 commits on `supabitapp/supacode` from `0150ceaf` (v0.8.0) through `c4e9be3b` (v0.8.1, 2026-04-19). Significant additions:

- **Tuist migration** (`02d75cd5` + ~20 follow-ups) — upstream replaced the checked-in Xcode project with a generated Tuist workspace. Driven by a `release-tip` archive regression in the new upstream CLI Xcode target, which archived with `SKIP_INSTALL = NO`, polluted the archive with a command-line product, and broke `developer-id` export, plus configuration sprawl across pbxproj, Makefile, CI workflows, and in-source telemetry key patching.
- **CLI tool** (`e57d744d`, #227) — Unix-socket upstream CLI with `open`/`worktree`/`tab`/`surface`/`repo`/`settings`/`socket` subcommands. Orchestration-focused, dispatches via deeplink URLs.
- **Script CLI + deeplinks** (`788dcff4` #253, `1f38a0c1` #246) — multi-script per repo, `worktree run --script UUID`, `worktree script list`.
- **Folder (non-git) repo support** (`68e44966`, #257); atomic `sidebar.json` state (`7981cf34`, #254); Icon Composer app icon for macOS 26 Liquid Glass (`f37b698f`, #230).
- **Ghostty `toggle-background-opacity`** (`1792e377`, #225) — same feature fork already implements via `5ca2bf4e` (2026-03-21, 3 weeks earlier).
- Misc Ghostty fixes and editor integrations (RubyMine #248, surface width #233, local URL paths #236, split-preserve-zoom #241, openFinder→openWorktree rename #247).

### Decisions

- **Tuist migration**: **Skip.** Fork sidesteps the `release-tip` archive bug by construction — `MaestroCLI` is a SwiftPM `executableTarget`, not an Xcode target, and is pre-copied into `Resources/maestro-cli/` as a folder reference. Archives already contain only `Products/Applications/Maestro.app`; `/usr/local/bin/maestro` symlinks into `/Applications/Maestro.app/Contents/Resources/maestro-cli/maestro`. Migrating would force rewriting the `/release` skill, notarization flow, appcast generation, and every rebrand patch for zero functional gain.
- **CLI (#227, #253, #246)**: **Skip.** Fork's `maestro` CLI targets agent scripting (`send`/`key`/`read` with stdin piping, output capture, timeout, keyboard token synthesis); upstream's CLI targets orchestration (`worktree archive/pin/delete`, `tab/surface new/split/close`, `repo`/`settings`/`socket`). The two are orthogonal, not duplicative. Future work may selectively port upstream's orchestration commands into `MaestroCLI`'s envelope-based transport, but nothing forces action today.
- **Ghostty `#225`**: **Defer to next sync of the affected files.** Upstream version is slightly cleaner — state on `GhosttyRuntime` instead of per-view (fixes multi-split-same-window ambiguity), reset on config reload, early-return in fullscreen, Bool return, debug logs. No user-visible bug in fork. When next editing `GhosttySurfaceView.swift` / `GhosttySurfaceBridge.swift` / `GhosttyRuntime.swift`, replace fork's implementation with upstream's and preserve the fork-only `chromeBackgroundColor(...)` call in `applyWindowBackgroundAppearance`.
- **Everything else**: Nothing user-facing for the fork. Re-evaluate on next review.

---

## 2026-04-08 — Full upstream review & change-list format migration

### Upstream changes reviewed

Reviewed all upstream (`supabitapp/supacode`) commits from our last sync through `0150ceaf` (v0.8.0). Key additions:

- **Deeplinks** (`a7f6d81f`) — new deeplink handling
- **Coding agent hook system** (`61356be1`) — hooks for Claude Code and Codex
- **Auto-hide tab bar for tmux** (`dc8eb02e`) — new setting
- **Inhibit command on script & single-tab bar hiding** (`301cf398`)
- **Auto-delete archived worktrees** (`666d440d`) — configurable retention period
- **Terminal layout persistence and restoration** (`771e4aab`)
- **Global worktree settings** (`c29ee5a5`) — global defaults with per-repo overrides
- **Merged worktree action picker** (`4db25220`) — replaces auto-archive toggle
- **Global defaults for copy flags and merge strategy** (`ce214902`) — overlaps with our #178

### Decisions

- **#178 (global defaults)**: Upstream added `ce214902` which covers global defaults for copy flags and merge strategy. Our fork branch `feat/issue-178-global-defaults` (`c7a10bd0`) implements the same concept. On next upstream sync, check for conflicts and prefer upstream's implementation where equivalent; keep fork extensions if any.
- **#173, #177**: Both PRs already merged.
- **change-list.md format**: This file is no longer maintained as a per-commit tracking table. It is now a dated log of upstream reviews and fork decisions. Use the `/check-upstream-changes` command to generate diffs against the baseline.

---

## Old Log

The table below was the original per-commit tracking format, preserved for reference.

| summary | commit hash | status |
| --- | --- | --- |
| Fix initial prompt path by normalizing trailing slash so working directory is set correctly on launch. | `fbfeec4` | Merged upstream |
| Align embedded Ghostty accessibility with Ghostty.app so AX-driven dictation/transcription tools like Typeless can recognize terminal panes correctly. | `aa57f08` | Merged upstream |
| Add fork sync and personal release workflow docs plus helper scripts (`sync-upstream-main.sh`, `release-to-fork.sh`). | `3599f5f` | Fork only |
| Remove `Cmd+Delete` shortcut from worktree archive actions, so the key can be handled by Ghostty/terminal behavior. | `022bb87` | Fork only |
| Harden fork release script: detect target repo from `origin` and add fallback (`gh api` + upload) when `gh release create` fails. | `058177e` | Fork only |
| Add local app notarization flow to fork release script (Developer ID signing + `notarytool` + stapling) for personal releases. | `a66c4b2` | Fork only |
| Clarify fork customization guidance and release workflow docs for this fork. | `b7f4e0b` | Fork only |
| Ignore local build artifacts in fork working tree to reduce noise. | `cccd36d` | Fork only |
| Harden upstream sync script/docs with deterministic fetch/merge flow and safer failure handling. | `56deb49` | Fork only |
| Add repo-scoped custom command buttons with configurable icon/title/command/execution mode and shortcut overrides. | `76046bc` | Fork only |
| Refine custom shortcut editor layout by tightening modifier symbol and toggle spacing. | `b5c58e4` | Fork only |
| Execute Terminal Input custom commands by injecting return key so the command runs immediately. | `562042f` | Fork only |
| Disable push-triggered `tip` release workflow in fork to avoid expected CI failures. | `85b3fd7` | Fork only |
| Enforce notarized-only fork releases; block non-notarized publishing path in release script and docs. | `2ab70fd` | Fork only |
| Move repo-scoped settings files into the fork's application data directory with legacy migration from repo root files. | `ea9259f` | Fork only |
| Add `/fork-release` slash command for upstream sync and private release workflow. | `64829dc` | Fork only |
| Add diff window with file tree sidebar and YiTong DiffView for viewing worktree changes. | `0d03848`, `09194c4` | Fork only |
| Wire up diff badge click in worktree row, `Cmd+]` shortcut, and Show Diff menu item. | `59dc4f6` | Fork only |
| Preload all file contents on diff window open for instant file switching. | `5850576` | Fork only |
| Add toolbar with sidebar toggle, diff style picker (split/unified), `Cmd+W` close, and window frame persistence. | `8985fc2` | Fork only |
| Add Canvas (Live Sessions) feature: free-form view displaying all open tabs as draggable, resizable cards in a balanced grid layout with pinch-to-zoom (cursor-anchored), two-finger scroll panning, organize button, and fit-to-view on open. | `2c1d9aa`…`80df1b1` | Fork only |
| Render full split pane layout in Canvas cards with `pinnedSize` propagation through the split tree to prevent terminal reflow during zoom. Enable resize handles on all four edges and corners. | `12496d5` | Fork only |
| Show all open tabs (not just active) as separate cards in Canvas; per-tab layout, focus, resize, and occlusion management. | `e5992ea` | Fork only |
| Fix Canvas grid layout: batch positioning to avoid overlap, stale layout cleanup, and organize/fit-to-view helpers. | `80df1b1`, `2653c06` | Fork only |
| Add two-finger scroll to pan canvas via NSView scroll-wheel interception. | `2738c24` | Fork only |
| Fix canvas pinch-to-zoom to anchor on cursor position instead of origin. | `c24e092` | Fork only |
| Add PreToolUse hook to block `gh pr create` targeting upstream; PRs must explicitly target fork. | `9970560` | Fork only |
| Add PR target rule to CLAUDE.md: always target the fork, never upstream. | `962ba62` | Fork only |
| Rebrand user-facing identity to the fork brand: app name, icon, bundle display name, settings file paths, subsystem identifiers, and about/UI strings. | `5f7d84a`…`5676418` | Fork only |
| Add public release infrastructure: Sparkle EdDSA key setup, date-based version scheme (`YYYY.M.DD`), full release script with DMG/notarization/appcast, `install-release` Makefile target, `/release` and `/sync-upstream` commands. | — | Fork only |
| Parallelize repository startup loading to speed up launch with many repos. | `8dd8eac` | Merged upstream |
| Run bundled `wt` binary directly instead of shell discovery for faster worktree operations. | `ed27b31` | Merged upstream |
| Evolve Canvas card layout algorithm (waterfall → MaxRects → combined row-break + waterfall packing) for better space utilization; auto-arrange cards on first Canvas entry per session; improved fit-to-view scaling. | `15bafd1`…`fc81375` | Fork only |
| Add Canvas toggle shortcut; auto-focus the previously active card when entering Canvas; exit Canvas to the focused worktree+tab; move Canvas and Show Diff to View menu. | `38a6361`, `3c4dc3c`, `17df275`, `d9dde25` | Fork only |
| Implement Ghostty `prompt-title` and `open-config` callbacks: surface prompts update tab titles; open-config opens Ghostty config in default text editor. | `2b55336`…`1352165` | Fork only |
| Route Ghostty window actions (`toggle_fullscreen`, `toggle_maximize`, `toggle_background_opacity`, `quit`, `close_window`) through Maestro; quit goes through TCA `requestQuit` for confirm-before-quit. | `5ca2bf4`…`4732780` | Fork only |
| Filter duplicate and unsupported Ghostty actions from command palette. | `512c5b3`, `c8c562f` | Fork only |
| Add command finished notification for long-running terminal commands with configurable duration threshold; Canvas highlights the entire title bar for unseen notifications, tracked per-tab. | `182e165`…`d7bb4b6` | Fork only |
| Mark notifications as read on key input to focused terminal surface; suppress command finished notification after recent user interaction. | `26968c1`, `2db9ae5` | Fork only |
| Add repository snapshot startup cache to skip full git scan on re-launch when worktrees haven't changed. | `7136591` | Pending upstream (#162) |
| Fix unicode paths in diff and untracked file output. | `1b32a26` | Fork only |
| Fix settings migration to copy instead of move, preserving the legacy upstream data directory for compatibility. | `07121b6` | Fork only |
| Use Claude to generate user-facing release notes; skip generation when pre-written notes exist. | `64d0928`, `849b5cf` | Fork only |
| Remove CI release workflows (`release.yml`, `release-tip.yml`) and make tip update channel equivalent to stable; releases are now handled locally via `/release` skill. | `7f79078`, `4546b66` | Fork only |
