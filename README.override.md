# Tinycast fork features

This file tracks user-requested features added to the fork. Keep one entry per feature as its behavior evolves.

## 1. Activate an exact user alias with Space

**Requirement.** In the launcher, an unmodified Space activates an entry only when the query exactly matches its user-defined alias. Partial aliases and ordinary app names keep normal typing behavior.

**Implementation.** `RootPaletteView` intercepts Space on the focused search field, where printable keys are otherwise consumed. Through `PaletteScreen.spaceActivation(matching:)`, `LauncherScreen` compares the normalized query with `AppIndex.userAlias(for:)` among visible entries and activates the match. Modified keys, text composition, and other focused controls do not trigger it.

**Code.** `Tinycast/Palette/RootPaletteView.swift`, `Tinycast/Palette/PaletteScreen.swift`, `Tinycast/Features/Launcher/UI/LauncherScreen.swift`, `Tinycast/Features/Launcher/Service/AppIndex.swift`.

## 2. Summon Window across Spaces and displays

**Requirement.** Add a separate **Summon Window** command and shortcut under Settings › Navigation. List eligible windows from every Space on every display, show `Space ID @ Screen ID`, place windows already in the palette display's current Space last, and move the exact selected window into that Space on Return. Keep the existing **Switch Windows** behavior, which activates a window in its original Space.

**Implementation.**

- `WindowSummonInventory` combines ScreenCaptureKit window IDs, including off-screen windows, from `SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)` with a per-Space WindowServer scan using `SLSCopyManagedDisplaySpaces`, `CGSCopyWindowsWithOptionsAndTags(..., 0x7)`, and `SLSWindowQueryWindows`. This finds inactive-Space windows that the existing AX-based `WindowSwitchSweep` can omit.
- The inventory filters helper surfaces and windows confirmed to have no Space membership. It does not reject a candidate solely because its Accessibility window is unavailable before the move. `WindowSummonLocation` formats Space/display IDs, and `WindowSummonOrder` puts other Spaces ahead of the destination Space, including during search.
- `WindowSummonCoordinator` moves the selected `CGWindowID` with `SLSBridgedMoveWindowsToManagedSpaceOperation`, then matches the same ID through Accessibility to place and focus it. It handles fullscreen sources and checks Accessibility and Screen Recording permissions.

**Limits.** The move and AX-to-window-ID APIs are private. A failed Space lookup can still show `? @ ?`, and AX matching or focus can fail after a confirmed move. Listing a row does not guarantee a complete move-and-focus result.

**Code.** `Tinycast/Features/WindowSwitcher/Service/WindowSummonInventory.swift`, `Tinycast/Platform/WindowSystemBridge.m`, `Tinycast/Features/WindowSwitcher/Model/WindowSummonLocation.swift`, `Tinycast/Features/WindowSwitcher/UI/WindowSummonCoordinator.swift`, `Tinycast/Features/Settings/Panes/NavigationSettingsView.swift`.
