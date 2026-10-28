# Tinycast

<img src="docs/screenshot.png" alt="Tinycast command palette" width="720">

**A free, native macOS launcher that runs Raycast extensions.** No account, no subscription,
no Electron. Requires macOS 26 or later.

This is a personal fork of [Tinycast](https://github.com/abue-ammar/tinycast), maintained by konata.
It follows upstream where possible and keeps the setup already on this Mac.

## Features

- **Launch and search:** apps, files, menu items, the dictionary, and Apple Shortcuts
- **Clipboard history** for text and images, plus snippets and quicklinks
- **Window management**, with saved layouts and rooms
- **Calculator** with currency conversion, plus notes, an emoji picker, and calendar
- **Global and per-app hotkeys**
- **Raycast extensions**, running natively in JavaScriptCore
- **Raycast import** that brings over your existing setup

## Fork features

- **Summon Window** across Spaces and displays, with `Space ID @ Screen ID` shown beside each window
- **Blue current-Space titles** in Summon Window, so windows already on the palette's display stand out
- **Exact alias activation with Space** in the launcher
- **Personal release builds and updates** from this repository

## Install

Download the latest zip from [Releases](https://github.com/konata/tinycast/releases), expand it, and
move `Tinycast.app` to `/Applications`.

Builds are self-signed. If macOS quarantines a downloaded copy, run
`xattr -dr com.apple.quarantine /Applications/Tinycast.app` once.
