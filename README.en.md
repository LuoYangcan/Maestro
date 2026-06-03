<p align="center">
  <img src="doc/maestro-icon.png" width="128" alt="Maestro">
</p>

<h1 align="center">Maestro</h1>

<p align="center">
  A native macOS terminal for orchestrating AI coding agents in parallel.
</p>

<p align="center">
  <a href="README.md">中文</a> · English
</p>

<p align="center">
  <a href="https://github.com/LuoYangcan/Maestro/releases/latest/download/Maestro.dmg"><b>Download</b></a>
</p>

---

Maestro is a personal fork of [Prowl](https://github.com/onevcat/Prowl) (itself a fork of [Supacode](https://github.com/supabitapp/supacode)), maintained mostly for my own day-to-day use with my own customizations on top. Built on [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) and [libghostty](https://github.com/ghostty-org/ghostty).

> Feature overview coming later.

## Install

- **Download:** [Maestro.dmg](https://github.com/LuoYangcan/Maestro/releases/latest/download/Maestro.dmg) (notarized)
- **Requires:** macOS 26.0+

## Develop & build

Requires [mise](https://mise.jdx.dev/) for zig / swiftlint and related tooling.

```bash
make build-ghostty-xcframework   # Build GhosttyKit from Zig source
make build-app                   # Build the macOS app (Debug)
make run-app                     # Build, launch, and stream logs
make install-dev-build           # Build Debug and install to /Applications
make install-release             # Build Release, sign locally, install to /Applications
```

```bash
make check                       # Format changed files + swift-format lint + SwiftLint
make test                        # Run unit tests
make build-cli                   # Build the maestro CLI
```

## Credits

Standing on the shoulders of [Prowl](https://github.com/onevcat/Prowl) and [Supacode](https://github.com/supabitapp/supacode).

## License

[FSL-1.1-ALv2](LICENSE)
