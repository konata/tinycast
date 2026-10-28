# Tinycast

<img src="docs/screenshot.png" alt="Tinycast command palette" width="720">

**A free, native macOS launcher that runs Raycast extensions.** No account, no subscription,
no Electron. Requires macOS 26 or later.

- **Launch and search:** apps, files, menu items, the dictionary, and Apple Shortcuts
- **Clipboard history** for text and images, plus snippets and quicklinks
- **Window management**, with saved layouts and rooms
- **Calculator** with currency conversion, plus notes, an emoji picker, and calendar
- **Global and per-app hotkeys**
- **Raycast extensions**, running natively in JavaScriptCore
- **Raycast import** that brings over your existing setup

## Install

Download the latest zip from [Releases](https://github.com/konata/tinycast/releases), expand it, and
move `Tinycast.app` to `/Applications`.

Builds are self-signed. If macOS quarantines a downloaded copy, run
`xattr -dr com.apple.quarantine /Applications/Tinycast.app` once.

## Documentation

| I want to…                            | Read                                                            |
| ------------------------------------- | --------------------------------------------------------------- |
| build and run it locally              | [development.md](docs/development.md)                           |
| understand how it's wired             | [architecture.md](docs/architecture.md)                         |
| know how code here is written         | [standards.md](docs/standards.md)                               |
| verify a change before a PR           | [testing.md](docs/testing.md)                                   |
| add or restyle UI                     | [ui.md](docs/ui.md)                                             |
| dig into one feature                  | [docs/features/](docs/README.md#features)                       |
| package a release                     | [release.md](docs/release.md)                                   |
| contribute or report a security issue | [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) |

The full docs index is at [docs/README.md](docs/README.md). AI agents should start with
[AGENTS.md](AGENTS.md).

## Repository layout

| Path                    | What's there                                               |
| ----------------------- | ---------------------------------------------------------- |
| `Tinycast/App/`         | entry point and `AppCore`, the composition root            |
| `Tinycast/Features/`    | one folder per feature                                     |
| `Tinycast/Palette/`     | the launcher panel shell                                   |
| `Tinycast/Windows/`     | dialogs, HUDs, About, and other non-palette windows        |
| `Tinycast/DesignSystem/`| shared visual primitives and `Theme`                       |
| `Tinycast/Platform/`    | system shims such as permissions, paths and signposts      |
| `Tests/`                | standalone test harnesses, run by `./Scripts/run-tests.sh` |
| `Scripts/`              | tests, lint, data generators, packaging                    |
| `website/`              | the project site                                           |

`project.yml` is the source of truth for the project. Run `xcodegen generate` after editing it.

## Contribute

Report bugs and ideas in [Issues](https://github.com/konata/tinycast/issues). Before opening a
PR, read [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Tinycast is an independent fork of [Tinycast](https://github.com/abue-ammar/tinycast), created by
Abue Ammar and contributors. It is not an official Tinycast release. Modified by konata in 2026.
Tinycast modifications copyright © 2026 konata. Licensed under AGPL-3.0-or-later. See
[LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
