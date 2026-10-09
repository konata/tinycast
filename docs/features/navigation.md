# Navigation

Three commands share one switch: **Switch Windows** raises a chosen window in its existing Space,
**Summon Window** moves one from another Space or display to the palette's current Space, and
**Search Menu Bar Items** presses an item in the front app's menu bar. Menu search has its own page —
[menu-search.md](menu-search.md) — because its internals are a menu walk; this page owns the window
commands and the pane they share.

Ships **off**. Settings › Navigation is the switch, and while it is off none of the commands is in
the launcher and their still-recorded shortcuts do nothing.

## Invariants

- **The sweep is synchronous, and that is deliberate.** `WindowSwitchSweep.snapshot` visits apps and
  their windows — one level, two AX reads each — where the menu walk descends a tree. A
  `Task.detached` here would buy a "Reading windows…" state nobody would ever see, and cost a
  revision counter to keep superseded sweeps from publishing. `WindowInventory` made the same call.
- **A live `AXUIElement` never leaves the main actor, and never outlives the show.** The pure entry
  carries a `handle`; `WindowSwitchSession` holds the `handle → Element` table `@ObservationIgnored`
  and drops it in `reset()`, which `hidePalette` and every mode change call.
- **Nothing in `Model/` knows what a window is.** `WindowSwitchEntry` takes `appRank` as a number
  someone else measured, so `WindowSwitchOrder` and `WindowSwitchQuery` stay Foundation-only and the
  harness compiles the shipped sources.
- **The order is total.** `(isMinimized, appRank, appName, handle)` — so a sweep that enumerated apps
  in a different order sorts identically, and minimized windows are always one run at the end rather
  than interleaved.
- **Accessibility is gated twice**, on show and again on activate: a grant revoked while the palette
  is open must not reach `AXUIElementPerformAction`.
- **Activation hides with `restoreFocus: false`.** Restoring focus reactivates the displaced app,
  which races the raise and can land on the wrong window — the same reason a Space command does it.
- **`AXWindowAccess` stays the one AX window layer.** `unminimize` and `focus` live there rather
  than in a second AX shim, and Window Layouts brings its frontmost window forward through `focus`.
- **Summon Window selects by `CGWindowID`.** Its list comes from ScreenCaptureKit, not the AX sweep;
  the AX element is matched by ID only after macOS moves the selected window. Matching titles would
  pick the wrong window when an app has two documents with the same name.
- **The destination is the palette's display at ↵.** The panel joins all Spaces and may be dragged,
  so its own window ID and its initial placement cannot identify the destination Space.

## How it is put together

| Piece | Holds |
| --- | --- |
| `Model/WindowSwitchEntry.swift` | one row: handle, app, title, minimized, rank, search fields |
| `Model/WindowSwitchOrder.swift` | the MRU sort, pure and total |
| `Model/WindowSwitchQuery.swift` | ranking over `SearchRelevance`, capped at 200 rows |
| `Service/WindowZOrder.swift` | the one `CGWindowList` call: per-pid front rank |
| `Service/WindowSwitchSweep.swift` | the AX sweep, and the live element table it hands back |
| `Service/WindowSwitchSession.swift` | the observable state — snapshot, filtered rows, elements |
| `UI/WindowSwitchCoordinator.swift` | show, activate, the switch, the failure reports |
| `UI/WindowSwitchScreen.swift` | the `PaletteScreen` conformance and the two empty states |
| `UI/WindowSwitchList.swift` | the list and its row: app icon, title, app name |
| `Service/WindowSummonInventory.swift` | ScreenCaptureKit's titled normal windows across displays and Spaces |
| `Service/WindowSummonSession.swift` | one asynchronous listing, its query and window ID targets |
| `UI/WindowSummonCoordinator.swift` | permission gates, destination Space, move and focus |
| `UI/WindowSummonScreen.swift` | the separate Summon Window palette mode |
| `Platform/WindowSystemBridge.{h,m}` | dynamic SkyLight Space operation and AX-to-window-ID lookup |

## Switch Windows recency without a private symbol

The MRU order comes from the window server's own front-to-back list: one
`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`, keeping
layer 0 — the normal window band, not the menu bar, Dock or overlay panels — and recording where each
pid first appears. Only `kCGWindowName` is permission-gated, and titles come from AX instead, so the
call needs no Screen Recording grant.

The rank is therefore **per app, not per window**: mapping a `CGWindowID` onto an `AXUIElement` needs
the private `_AXUIElementGetWindow`, and the app's own `kAXWindowsAttribute` order already gives the
windows inside one app front-to-back. An app with nothing on screen — everything minimized, or every
window on another Space — gets no rank at all and sorts after the ranked ones by name.

The alternative was a long-lived `NSWorkspace.didActivateApplicationNotification` observer with its
own LRU and its own lifetime. This needs neither, and it is right on the first summon after launch
rather than after the user has switched apps once.

## Switch Windows sweep

`WindowSwitchSweep` walks `WindowInventory.candidates()` — regular-policy, non-terminated, not us —
and takes every window whose subrole is `AXStandardWindow`. That is looser than
`WindowInventory.eligibleFrame` in two ways that both matter here: a **minimized** window is exactly
what a switcher is for, and a window on another Space reports no frame until it is raised, so
requiring one would hide it.

Each element gets a 0.2 s messaging timeout, the same as the layout inventory and the menu walk, so
one hung app cannot stall the switch.

The app icon rides on the entry as a `FileIconStamp` and its bundle URL, and the row draws it through
`EntryIconView(source: .file(stamp:))` — so `IconCache` decodes once per app however many windows it
contributes.

## Switching to a window

`activate` un-minimizes if it has to, raises the window inside its app, sets `AXFrontmost`, then calls
`NSRunningApplication.activate()`. All four steps are needed and none is redundant: the raise alone
orders the window inside an app that is not frontmost, and activating alone brings the app's *own*
front window forward rather than the chosen one. Activating is also what pulls another Space forward,
so the switcher needs no Space handling of its own.

Every step is allowed to fail quietly. What is reported is only the case the user can act on: the
window's app quit between the sweep and the ↵.

## Summoning a window

`WindowSummonInventory` asks `SCShareableContent` for off-screen windows as well as on-screen ones.
It keeps layer-zero windows with a nonempty title, a positive frame and a live owning application;
it does not apply `WindowInventory.candidates()`'s regular-app restriction. The palette reuses the
switcher's row, sort and fuzzy query, but stores `handle → (CGWindowID, app)` separately. Empty titles
are excluded because ScreenCaptureKit also returns many untitled helper surfaces, and a title is what
this command asks the user to choose.

ScreenCaptureKit needs **Screen Recording** for other apps' titles. Summon Window checks that grant and
Accessibility when opening and again on ↵; a missing grant prompts and offers the relevant System
Settings pane. Switch Windows keeps its Accessibility-only path. The capture usage description is in
`Info.plist`. Returning to Summon Window through palette Back or reopening a preserved palette starts
a fresh scan, so its window IDs cannot outlive the screen that showed them. If the first grant has not
become available to this process yet, the scan error tells the user to reopen Tinycast.

At ↵, the coordinator reads the palette panel's actual `NSScreen`, maps its display UUID through
`SLSCopyManagedDisplaySpaces` to that display's current Space, and hides the palette without restoring
the prior app's focus. Before each move attempt, a fresh ScreenCaptureKit listing confirms that the
selected `CGWindowID` still belongs to its app, including when it is on another Space.
`SLSBridgedMoveWindowsToManagedSpaceOperation` then moves that ID. The WindowServer updates Space
membership after the call returns, so the coordinator checks for up to two seconds before claiming
success. It resolves the same ID against that app's AX windows, unminimizes if needed, verifies or
corrects its position on the target display, and focuses it. If the AX element or final focus cannot
be confirmed, the Space move still stands and a notice says which step was incomplete.

SkyLight's move operation and `_AXUIElementGetWindow` are private macOS interfaces, looked up at
runtime by the small Objective-C bridge. On macOS 26.6.1, a disposable window moved from a second
display's Space 10 to the primary display's Space 6 and back without changing either display's active
Space. Other apps, minimized windows and full-screen Spaces still need integrated manual checks.

## Wiring

- **`CommandID.switchWindows`** (`command:switch-windows`), `CommandID.summonWindow`
  (`command:summon-window`) and `CommandID.searchMenuItems` are named by
  `SettingsTab.navigation.ownedCommands`, which is the whole of what moves them out of
  Settings › Commands: `LauncherItemsSection` filters on `settingsOwner == nil`, and `VisibilityStore`
  skips the `Enable Commands` category gate for a pane-owned command. None adds an
  `AppEntry.Kind`, a `HotKeyAction` case or a `VisibilityStore` category — they are plain `.command`
  entries.
- **`navigationEnabled`** (off) is the switch. `AppCore.observeFeatureSwitches` tracks it once and
  reprojects into all three coordinators; each owns only its own command and palette mode.
  `AppIndex.isCommandEnabled` feeds `hotKeys.allowsAction`, so their shortcuts go dead with the switch,
  and each `show()` re-guards the flag anyway.
- **`menuSearchDisabledApps`** (empty) is the exclusion list. It ships with no seeded entries, unlike
  the clipboard's: a menu read only ever happens because the user asked for one.
- **`menuSearchShowsAppleMenu`** (off) lists the Apple menu's own items. Off by default because that
  menu is identical under every app, so it would pad every snapshot with the same ~50 rows;
  [menu-search.md](menu-search.md) owns how it is applied.
- **The window commands ride in the pane's command section; menu search has its own section.**
  `FeatureCommandsSection` takes `excluding: [.searchMenuItems]` and the section draws that one
  command through `FeatureCommandRow`, so a command added to `ownedCommands` later still appears
  in the command section without a second edit. A list of excluded apps in a box of its own read as
  belonging to the pane rather than to one command, which is what this section exists to fix;
  `DisabledApplicationsList` is the shared half — the rows and the picker — that Settings ›
  Clipboard still wraps in a `DisabledApplicationsSection` of its own.
- The two menu-search settings ride in backups. The navigation switch does not grant Screen Recording
  or Accessibility; macOS controls those permissions independently.
- **There is deliberately no "Show in launcher" switch.** The per-command checkboxes in
  `FeatureCommandsSection` already are one, and a second would be a switch over rows the pane lists.

## Testing

`Tests/window-switch-test.swift` covers the pure half: the handle-derived id, the untitled-window
fallback, the name/owner split in the search fields, the MRU order and its totality under a shuffled
sweep, the minimized run at the end, ranking, and the 200-row cap under both an empty and a
matching query.

The platform paths are not compiled into the harness and need manual verification, particularly:

1. A minimized window is listed last and ↵ un-minimizes it rather than doing nothing.
2. A window on another Space is listed, and ↵ pulls that Space forward.
3. An app with several windows lists them in its own front-to-back order, under one app rank.
4. An app quit between the summon and the ↵ reports rather than failing silently.
5. Summon Window lists titled windows on another display and Space, then ↵ moves the chosen ID to
   the palette's current display and Space without switching Spaces.
6. After dragging the palette to a different display, ↵ uses that display as the destination.
7. Revoking Screen Recording or Accessibility while the list is open reports the missing grant.
