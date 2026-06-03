# CLI Input Contract: `maestro` (v1)

Status: draft truth source for `#70` implementation.

This file defines **input-side** rules for the phase-1 CLI commands:

- `open`
- `list`
- `focus`
- `send`
- `key`
- `read`

It complements output contracts under `doc/contracts/cli/{open,list,focus,send,key,read}.md`.

---

## 1) Design goals

- One stable command grammar for both humans and agents.
- No hidden priority chains that make scripts nondeterministic.
- Parse once in CLI layer; app layer should receive already-normalized typed requests.
- Keep command behavior composable: `list -> focus/send/key/read`.

---

## 2) Global command model

### 2.1 Canonical form

```bash
maestro <subcommand> [target-selector] [command-args] [output-options]
```

### 2.2 Supported subcommands (v1)

- `open`
- `list`
- `focus`
- `send`
- `key`
- `read`

Global options (not subcommands):

- `--help`
- `--version`

### 2.3 Bare path entry

These are equivalent to `open` entry:

- `maestro`
- `maestro <path-like-first-arg>`
- `maestro open <path>`

Path-like first arg (v1):

- `/...`
- `./...`
- `../...`
- `~/...`
- `file://...`
- `.`
- `..`

### 2.4 `--` handling

`--` stops option parsing and forces following token parsing as positional arguments.

- `maestro -- ./focus` MUST be treated as path entry (`open`), not subcommand `focus`.
- `maestro open -- --weird-dir` MUST treat `--weird-dir` as path.

---

## 3) Target selector contract (shared)

### 3.1 Selector flags

- `-t <value>` / `--target <value>` — auto-resolve: try pane UUID → tab UUID → worktree id/name/path.
- `--worktree <id|name|path>` — explicit worktree selector.
- `--tab <id>` — explicit tab UUID selector.
- `--pane <id>` — explicit pane UUID selector.

### 3.2 Positional target shorthand

`focus` and `read` accept an optional positional argument as auto-target:

```bash
maestro focus <target>
maestro read <target> --last 50
```

`send` and `key` use argument count to disambiguate:

- `maestro send "text"` — 1 arg → text to current pane.
- `maestro send <target> "text"` — 2 args → auto-target + text.
- `maestro key enter` — 1 arg → key token to current pane.
- `maestro key <target> enter` — 2 args → auto-target + key token.

Positional targets are ignored when flag selectors (`-t`, `--worktree`, `--tab`, `--pane`) are present.

### 3.3 Mutual exclusivity (hard rule)

Exactly **zero or one** selector is allowed.

- `0 selector`: operate on current focused target (where command allows it).
- `1 selector`: resolve with that selector.
- `>1 selector`: error `INVALID_ARGUMENT`.

This is preferred over implicit precedence because it is easier to reason about in scripts.

### 3.4 Resolution rules

- `--pane`: exact pane.
- `--tab`: current focused pane of target tab.
- `--worktree`: selected tab + focused pane in target worktree.
- `-t` / `--target` / positional: auto-resolve in order pane → tab → worktree.
- none: currently focused pane in current context.

If required context does not exist:

- return command-specific not-found / no-active-pane error.

---

## 4) Common output flags

### 4.1 `--json`

All phase-1 commands MUST support `--json`.

- With `--json`, output MUST match corresponding schema in `schema.md`.
- Without `--json`, output is human-readable text.

### 4.2 Exit behavior

- Success: exit code `0`
- Failure: non-zero
- Error payload shape in JSON mode MUST follow command contract (`error.code`, `error.message`, optional `error.details`).

(Exact numeric non-zero codes can be refined later; error `code` string is the machine contract.)

---

## 5) Per-command input rules

## 5.1 `open`

### Grammar

```bash
maestro
maestro <path-like>
maestro open <path>
```

### Rules

- `maestro` without path is valid and means “open app / bring to front”.
- `maestro <path-like>` is first-class, not shorthand hack.
- `maestro open <path>` is explicit equivalent for scripts.
- For all open-entry forms, if app is not running, CLI MUST launch Maestro and complete the open/focus flow.
- Path MUST be normalized by CLI:
  - expand `~`
  - resolve relative path to absolute path
  - resolve `file://`
  - normalize `.` / `..`
- If provided path does not exist or is not a directory: error (`PATH_NOT_FOUND` / `PATH_NOT_DIRECTORY`).

## 5.2 `list`

### Grammar

```bash
maestro list [--json]
```

### Rules

- `list` MUST NOT accept target selectors in v1 (it is global discovery).
- Extra positional args: `INVALID_ARGUMENT`.

## 5.3 `focus`

### Grammar

```bash
maestro focus [<target>] [--json]
maestro focus [-t <...> | --worktree <...> | --tab <...> | --pane <...>] [--json]
```

### Rules

- Optional positional `<target>` is auto-resolved (pane → tab → worktree).
- Flag selectors override positional target.
- No selector means “focus current target and bring app front”.
- More than one selector is invalid.

## 5.4 `send`

### Grammar

```bash
maestro send [flags] <text>
maestro send [flags] <target> <text>
printf '...' | maestro send [flags]
printf '...' | maestro send [flags] -t <target>
```

Where `[flags]` includes `[--no-enter] [--no-wait] [--capture] [--timeout <seconds>] [--json]` and optional selector flags (`-t`, `--worktree`, `--tab`, `--pane`).

### Rules

- Positional argument count determines interpretation:
  - 0 args: read text from stdin, send to current pane.
  - 1 arg: text to current pane.
  - 2 args: first is auto-resolved target, second is text.
- Flag selector (`-t`, `--worktree`, `--tab`, `--pane`) overrides positional target.
- Input source is exactly one of positional text or stdin. Both: `INVALID_ARGUMENT`. Neither: `EMPTY_INPUT`.
- Default sends trailing Enter; `--no-enter` disables it.
- Default waits for command completion (requires shell integration); `--no-wait` disables it and returns immediately after delivery.
- `--timeout <seconds>` sets the maximum wait duration (default: 30, range: 1–300). Ignored when `--no-wait` is used.
- If the wait times out: `WAIT_TIMEOUT`.

## 5.5 `key`

### Grammar

```bash
maestro key [flags] <token>
maestro key [flags] <target> <token>
```

Where `[flags]` includes `[--repeat <n>] [--json]` and optional selector flags (`-t`, `--worktree`, `--tab`, `--pane`).

### Rules

- Positional argument count determines interpretation:
  - 1 arg: key token to current pane.
  - 2 args: first is auto-resolved target, second is key token.
- Flag selector overrides positional target.
- Exactly one key token required.
- Token parsing is case-insensitive; canonical output token is lowercase kebab-case.
- Alias normalization follows `key.md`.
- `--repeat` default is `1`, range `1...100`.
- `--repeat` out of range: `INVALID_REPEAT`.

## 5.6 `read`

### Grammar

```bash
maestro read [<target>] [--last <n>] [--json]
maestro read [-t <...> | --worktree <...> | --tab <...> | --pane <...>] [--last <n>] [--json]
```

### Rules

- `--last` optional; if omitted, mode is `snapshot`.
- `--last <n>` requires integer `n >= 1`; otherwise `INVALID_ARGUMENT`.
- At most one `--last` value.

---

## 6) Reserved command tokens (v1)

These tokens are reserved as first command token:

- `open`
- `list`
- `focus`
- `send`
- `key`
- `read`

If first token matches a reserved command, CLI MUST parse as subcommand unless forced by `--` path form.

`--help` / `--version` are handled as global options, not subcommands.

---

## 7) Normalized request model (input -> typed request)

CLI parser MUST produce one normalized typed request before transport.

Example shape:

```swift
struct CommandEnvelope {
  var output: OutputMode // text | json
  var command: Command
}

enum Command {
  case open(OpenInput)
  case list(ListInput)
  case focus(FocusInput)
  case send(SendInput)
  case key(KeyInput)
  case read(ReadInput)
}
```

This model is the handoff contract to app/transport layer.

---

## 8) Examples (valid / invalid)

Valid:

```bash
maestro .
maestro open ~/Projects/Maestro
maestro focus 6E1A2A10-D99F-4E3F-920C-D93AA3C05764          # auto-resolve pane UUID
maestro focus --pane 6E1A2A10-D99F-4E3F-920C-D93AA3C05764    # explicit pane
maestro focus main                                            # auto-resolve worktree name
maestro send "echo hello"                                     # text to current pane
maestro send 6E1A2A10-D99F-4E3F-920C-D93AA3C05764 "echo hi"  # target + text
printf 'git status' | maestro send --worktree Maestro --json
maestro key enter                                             # key to current pane
maestro key 6E1A2A10-D99F-4E3F-920C-D93AA3C05764 ctrl-c      # target + key
maestro read 6E1A2A10-D99F-4E3F-920C-D93AA3C05764 --last 200 # positional target + flag
```

Invalid:

```bash
maestro focus --pane <id> --tab <id>        # multiple selectors
maestro focus --pane <id> <positional>      # flag + positional (flag wins, positional ignored)
maestro send "echo hi" < /tmp/input.txt     # two input sources
maestro key --repeat 0 enter                 # repeat out of range
maestro list --pane <id>                     # list does not accept selector
```

---

## 9) Non-goals (v1)

- No complex selector query language (`--where ...`).
- No streaming mode for `read`.
- No macro system for `key`.
- No dual parser implementations in v1.
