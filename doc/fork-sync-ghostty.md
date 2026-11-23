# Ghostty Fork Sync

Maestro embeds GhosttyKit from `ThirdParty/ghostty`. The submodule points to the `onevcat/ghostty` fork so Maestro can carry small embedded API patches that are not yet upstream.

## Branch Model

- Upstream remote: `https://github.com/ghostty-org/ghostty`
- Fork remote: `https://github.com/onevcat/ghostty.git`
- Per-version patched branches: `release/v<UPSTREAM_TAG>-patched`
- Current patched branch: `release/v1.4.0-patched` (`9811138fb6acaf1f1737e5148b007070601f4948`)

Each patched branch starts at the matching upstream tag and only adds fork patches. Do not rewrite an existing patched branch after publishing it.

## Patches Dropped on `v1.4.0`

- Foreground process group patches (`a28412716`, `fe714860c`) — replaced by upstream `ghostty_surface_foreground_pid`.
- Text free ABI backport (`48365577c`) — included upstream in `v1.4.0`.

## Upgrade To A New Ghostty Tag

```bash
cd ThirdParty/ghostty

git fetch upstream --tags
git fetch origin

PREV=v1.4.0
NEXT=v1.4.1
PATCH_TIP=9811138fb6acaf1f1737e5148b007070601f4948

git checkout -b "release/${NEXT}-patched" "${NEXT}"
git cherry-pick $(git rev-list --reverse --no-merges "${PREV}..${PATCH_TIP}")
git push -u origin "release/${NEXT}-patched"

cd ../..
git -C ThirdParty/ghostty checkout "release/${NEXT}-patched"
git add ThirdParty/ghostty
git commit -m "chore(ghostty): bump submodule to ${NEXT}-patched"
make sync-ghostty
make build-app
```

## Force Push Policy

Do not force-push `release/v*-patched` branches. If a cherry-pick needs repair, use a temporary fix branch, validate it, then fast-forward the patched branch.

## Build Note

Ghostty `v1.4.0` requires Zig `0.17.0` (`minimum_zig_version` in `ThirdParty/ghostty/build.zig.zon`), pinned in `mise.toml`.

The previous Xcode 26.3 pin from the `v1.3.1` / Zig `0.15.2` line is no longer required: Zig `0.16+` fixes linking against `arm64e`-only `libSystem.tbd` in macOS SDK 26.4+ (`ziglang/zig#31658`). Both `make sync-ghostty` and `make build-app` now build with the default Xcode (verified on Xcode 27.2).

If a freshly installed Xcode lacks the Metal toolchain needed to compile `Ghostty.metallib`, install it once with:

```bash
xcodebuild -downloadComponent MetalToolchain
```

The `Makefile` passes `-Dversion-string` from `ThirdParty/ghostty/build.zig.zon` so non-semver release tags on `onevcat/ghostty` (such as `xcframework-*-prowl-v1`) do not trip Ghostty's `Config.zig` tag check.
