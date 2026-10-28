# Tinycast fork features

This file tracks user-requested features added to the fork. Keep one entry per feature as its behavior evolves.

## 1. Activate an exact user alias with Space

**Requirement.** In the launcher, an unmodified Space activates an entry only when the query exactly matches its user-defined alias. Partial aliases and ordinary app names keep normal typing behavior.

**Implementation.** `RootPaletteView` intercepts Space on the focused search field, where printable keys are otherwise consumed. Through `PaletteScreen.spaceActivation(matching:)`, `LauncherScreen` compares the normalized query with `AppIndex.userAlias(for:)` among visible entry and fallback rows, then activates the match. Modified keys, text composition, menus, and other focused controls do not trigger it. This remains a fork feature; upstream has no equivalent patch.

**Code.** `Tinycast/Palette/RootPaletteView.swift`, `Tinycast/Palette/PaletteScreen.swift`, `Tinycast/Features/Launcher/UI/LauncherScreen.swift`, `Tinycast/Features/Launcher/Service/AppIndex.swift`.

## 2. Summon Window across Spaces and displays

**Requirement.** Add a separate **Summon Window** command and shortcut under Settings › Navigation. List eligible windows from every Space on every display, show `Space ID @ Screen ID`, place windows already in the palette display's current Space last, and move the exact selected window into that Space on Return. Keep the existing **Switch Windows** behavior, which activates a window in its original Space.

**Implementation.**

- `WindowSummonInventory` combines ScreenCaptureKit window IDs, including off-screen windows, from `SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)` with a per-Space WindowServer scan using `SLSCopyManagedDisplaySpaces`, `CGSCopyWindowsWithOptionsAndTags(..., 0x7)`, and `SLSWindowQueryWindows`. This finds inactive-Space windows that the existing AX-based `WindowSwitchSweep` can omit.
- The inventory filters helper surfaces and windows confirmed to have no Space membership. It does not reject a candidate solely because its Accessibility window is unavailable before the move. `WindowSummonLocation` formats Space/display IDs, and `WindowSummonOrder` puts other Spaces ahead of the destination Space, including during search.
- `WindowSummonCoordinator` moves the selected `CGWindowID` with `SLSBridgedMoveWindowsToManagedSpaceOperation`, then matches the same ID through Accessibility to place and focus it. It handles fullscreen sources and checks Accessibility and Screen Recording permissions.

**Limits.** The move and AX-to-window-ID APIs are private. A failed Space lookup can still show `? @ ?`, and AX matching or focus can fail after a confirmed move. Listing a row does not guarantee a complete move-and-focus result.

**Code.** `Tinycast/Features/WindowSwitcher/Service/WindowSummonInventory.swift`, `Tinycast/Platform/WindowSystemBridge.m`, `Tinycast/Features/WindowSwitcher/Model/WindowSummonLocation.swift`, `Tinycast/Features/WindowSwitcher/UI/WindowSummonCoordinator.swift`, `Tinycast/Features/Settings/Panes/NavigationSettingsView.swift`.

## 3. Highlight current-Space window titles in Summon Window

**Requirement.** In Summon Window, show the central window title in blue when the window belongs to the palette display's current Space, including minimized windows. Keep other title colors, icons, trailing labels, selection styles, ordering, activation, and Switch Windows unchanged.

**Implementation.** `WindowSummonSession` derives current-Space handles from the inventory's Space memberships and an observable destination. `WindowSummonScreen` supplies them to `WindowSwitchList`, which applies `Theme.Colors.currentSpaceTitle` only to matching titles. Existing `TCCurrentManagedSpace` destination refreshes on display moves and `NSWorkspace.activeSpaceDidChangeNotification` update the title colors. The token uses appearance-aware `NSColor.systemBlue` rather than the configurable accent color.

**Limits.** Current Space means the active Space on the palette's display, not every display's active Space. Membership comes from the listing snapshot; externally moved windows may keep their old color until a fresh scan. A failed destination lookup marks no titles blue. Blue indicates membership, not a guaranteed move-and-focus result.

**Code.** `Tinycast/Features/WindowSwitcher/Service/WindowSummonSession.swift`, `Tinycast/Features/WindowSwitcher/UI/WindowSummonScreen.swift`, `Tinycast/Features/WindowSwitcher/UI/WindowSwitchList.swift`, `Tinycast/Features/WindowSwitcher/UI/WindowSummonCoordinator.swift`, `Tinycast/DesignSystem/Theme.swift`.

## 4. Versioned downloadable fork releases

**Requirement.** Increase the fork version and publish the current code through GitHub Actions, with downloadable releases and retained history.

**Implementation.** `.github/workflows/personal.yml` owns the personal build's `VERSION` (currently `0.12.3-konata.3`) and passes it as `MARKETING_VERSION`, with `github.run_number` as `CURRENT_PROJECT_VERSION`. Manual Personal build runs package the signed app using `ditto`, then use `gh release create --target` to publish `v<version>` with `Tinycast-<version>.zip`. Stable releases are marked Latest; Dev builds append `-dev.<run number>` and remain prereleases. Existing versioned releases are rejected rather than overwritten; bump `VERSION` for the next stable release. The old rolling release is retained.

Personal stable versions use `MAJOR.MINOR.PATCH-konata.N`: keep the triple at the merged upstream release, and increment `N` for every published fork build, whether the change came from an upstream merge or fork-only work. `N` never resets; after merging upstream `0.12.4`, `0.12.3-konata.3` is followed by `0.12.4-konata.4`. The in-app updater reads `konata/tinycast` releases and accepts that form as a stable update, while Dev builds remain outside the stable feed.

**Limits.** Personal builds target Apple silicon and macOS 26+, use a self-signed certificate, and may need quarantine removal after downloading. The updater installs only a release whose tag and app bundle carry the same accepted version string. Compilation and validation run in manually dispatched GitHub Actions workflows.

## 5. Personal builds update from the fork's releases

**Requirement.** Check for Updates reads this fork's GitHub releases rather than upstream's. The updater accepts the fork's stable `MAJOR.MINOR.PATCH-konata.N` tags in addition to plain `MAJOR.MINOR.PATCH` and upstream beta tags.

**Implementation.** `ReleaseFeed.repository` names `konata/tinycast`, so the daily check and release-note links resolve there. `AppVersion` carries an optional fork revision after the upstream triple, sorts it after that triple, and round-trips the full string because the installer compares it with `CFBundleShortVersionString`. Stable releases stay non-prerelease, while upstream beta parsing remains unchanged.

**Limits.** A fork release must keep its tag, workflow `VERSION`, and bundled `CFBundleShortVersionString` identical. Dev builds append `-dev.<run>` and are not offered through the stable updater. Intel remains unsupported by Personal builds because they publish only an arm64 zip.

**Code.** `Tinycast/Features/Updates/Model/ReleaseFeed.swift`, `Tinycast/Features/Updates/Model/AppVersion.swift`, `Tinycast/Features/Updates/Service/UpdateCheckStore.swift`, `.github/workflows/personal.yml`, `Tests/updates-test.swift`.
