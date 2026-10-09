import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class WindowSummonCoordinator {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: WindowSummonSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    private var spaceObserver: NotificationToken?

    init(
        settings: AppSettings, appIndex: AppIndex, session: WindowSummonSession,
        palette: PaletteState, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDestination() }
        }
        spaceObserver = NotificationToken(token, center: center)
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.summonWindow], settings.navigationEnabled)
        guard !settings.navigationEnabled else { return }
        cancel()
        if palette.mode == .summonWindows { palette.prepare(mode: .launcher) }
    }

    func cancel() { session.reset() }

    func show() {
        guard settings.navigationEnabled else { return }
        guard Permissions.ensureAccessibility() else {
            Task { [weak self] in await self?.reportAccessibilityFailure() }
            return
        }
        guard Permissions.ensureScreenRecording() else {
            Task { [weak self] in await self?.reportScreenRecordingFailure() }
            return
        }

        paletteCoordinator.togglePalette(mode: .summonWindows)
        scanIfNeeded()
    }

    func scanIfNeeded() {
        guard paletteCoordinator.isShowing(.summonWindows), !session.hasStarted else { return }
        guard Permissions.ensureAccessibility() else {
            Task { [weak self] in await self?.reportAccessibilityFailure() }
            return
        }
        guard Permissions.ensureScreenRecording() else {
            Task { [weak self] in await self?.reportScreenRecordingFailure() }
            return
        }
        session.begin()
        refreshDestination()
        session.filter(palette.query)
        session.retain(Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await WindowSummonInventory.snapshot()
                guard !Task.isCancelled, self.paletteCoordinator.isShowing(.summonWindows) else {
                    return
                }
                self.session.present(snapshot)
            } catch {
                guard !Task.isCancelled, self.paletteCoordinator.isShowing(.summonWindows) else {
                    return
                }
                self.session.fail()
                await self.core.showNotice(
                    title: "Couldn’t Read Windows",
                    message: "\(error.localizedDescription) If you just granted Screen Recording, reopen Tinycast.",
                    symbol: "macwindow.on.rectangle", tone: .danger)
            }
        })
    }

    func refreshDestination() {
        guard paletteCoordinator.isShowing(.summonWindows),
            let screen = paletteCoordinator.currentScreen,
            let uuid = AXScreens.uuid(of: screen)
        else { return }
        session.destination(TCCurrentManagedSpace(uuid as CFString))
    }

    func activate(_ entry: WindowSwitchEntry) {
        guard Permissions.ensureAccessibility() else {
            Task { [weak self] in await self?.reportAccessibilityFailure() }
            return
        }
        guard Permissions.ensureScreenRecording() else {
            Task { [weak self] in await self?.reportScreenRecordingFailure() }
            return
        }
        guard let target = session.target(for: entry.handle), !target.app.isTerminated else {
            Task { [weak self] in await self?.reportGone(entry) }
            return
        }
        guard let screen = paletteCoordinator.currentScreen,
            let uuid = AXScreens.uuid(of: screen)
        else {
            Task { [weak self] in await self?.reportMoveFailure(entry) }
            return
        }
        let spaceID = TCCurrentManagedSpace(uuid as CFString)
        guard spaceID != 0 else {
            Task { [weak self] in await self?.reportMoveFailure(entry) }
            return
        }
        guard TCSpaceType(spaceID) == 0 else {
            Task { [weak self] in await self?.reportDestinationFailure() }
            return
        }
        let canvas = AXGeometry(screens: NSScreen.screens).flip(screen.visibleFrame)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { [weak self] in
            await self?.move(entry, target: target, display: uuid, spaceID: spaceID, canvas: canvas)
        }
    }

    private func move(
        _ entry: WindowSwitchEntry, target: WindowSummonInventory.Target,
        display: String, spaceID: UInt64, canvas: CGRect
    ) async {
        let windowID = target.windowID
        guard (try? await WindowSummonInventory.contains(target)) == true else {
            await reportGone(entry)
            return
        }
        let sourceSpaces = TCWindowSpaceIDs(windowID) ?? []
        if target.isFullscreen || sourceSpaces.contains(where: { TCSpaceType($0.uint64Value) == 4 }) {
            guard await exitFullScreen(entry, target: target) else { return }
        }
        guard !Task.isCancelled else { return }
        let moved = !TCWindowIsInSpace(windowID, spaceID)
        if moved {
            // A second move can be ignored while the previous Space transition settles.
            for attempt in 0..<2 {
                if attempt > 0 {
                    guard (try? await WindowSummonInventory.contains(target)) == true else {
                        await reportGone(entry)
                        return
                    }
                }
                guard TCMoveWindowToSpace(windowID, spaceID) else {
                    await reportMoveFailure(entry)
                    return
                }
                for _ in 0..<10 {
                    if TCWindowIsInSpace(windowID, spaceID) { break }
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        return
                    }
                }
                if TCWindowIsInSpace(windowID, spaceID) { break }
            }
            guard TCWindowIsInSpace(windowID, spaceID) else {
                await reportMoveFailure(entry)
                return
            }
        }

        guard !target.app.isTerminated else {
            await reportGone(entry)
            return
        }
        if target.app.isHidden { _ = target.app.unhide() }
        let application = AXWindowAccess.application(for: target.app.processIdentifier, timeout: 0.2)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        var found: AXUIElement?
        while found == nil {
            found = AXWindowAccess.window(withID: windowID, in: application)
            if found != nil || clock.now >= deadline { break }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
        guard let window = found else {
            await reportPartial(entry, moved: moved,
                detail: "Tinycast couldn’t find its Accessibility window")
            return
        }
        if AXWindowAccess.bool(window, kAXMinimizedAttribute) == true {
            _ = AXWindowAccess.unminimize(window)
        }
        guard !AXWindowAccess.isFullScreen(window),
            !(TCWindowSpaceIDs(windowID) ?? []).contains(where: {
                TCSpaceType($0.uint64Value) == 4
            })
        else {
            await reportPartial(entry, moved: moved, detail: "it is still full screen")
            return
        }
        guard let frame = AXWindowAccess.frame(of: window) else {
            await reportPartial(entry, moved: moved, detail: "its position couldn’t be verified")
            return
        }
        if !canvas.contains(frame) {
            let landing = WindowPlacementEngine.clamped(frame, into: canvas)
            guard AXWindowAccess.setPosition(landing.origin, on: window) else {
                await reportPartial(entry, moved: moved,
                    detail: "it couldn’t be placed on this display")
                return
            }
        }
        guard let placed = AXWindowAccess.frame(of: window), placed.intersects(canvas) else {
            await reportPartial(entry, moved: moved,
                detail: "its display position couldn’t be verified")
            return
        }
        AXWindowAccess.focus(window, in: application, of: target.app)
        for _ in 0..<4 {
            let focused = AXWindowAccess.element(application, kAXFocusedWindowAttribute)
            if let focused, TCWindowIDForAXElement(focused) == windowID,
                TCWindowIsInSpace(windowID, spaceID),
                TCCurrentManagedSpace(display as CFString) == spaceID
            { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
        await reportPartial(entry, moved: moved, detail: "Tinycast couldn’t confirm focus")
    }

    private func exitFullScreen(
        _ entry: WindowSwitchEntry, target: WindowSummonInventory.Target
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let windowID = target.windowID
        let application = AXWindowAccess.application(for: target.app.processIdentifier, timeout: 0.2)
        guard let window = AXWindowAccess.window(withID: windowID, in: application) else {
            await reportFullScreenFailure(entry,
                detail: "Tinycast couldn’t identify its Accessibility window before moving it.")
            return false
        }
        if AXWindowAccess.isFullScreen(window) {
            guard AXWindowAccess.exitFullScreen(window) else {
                await reportFullScreenFailure(entry,
                    detail: "This app didn’t allow Tinycast to exit full screen.")
                return false
            }
        } else {
            let spaces = TCWindowSpaceIDs(windowID) ?? []
            guard !spaces.isEmpty, spaces.allSatisfy({ TCSpaceType($0.uint64Value) == 0 })
            else {
                await reportFullScreenFailure(entry,
                    detail: "Tinycast couldn’t verify this window’s full-screen state.")
                return false
            }
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            guard !Task.isCancelled else { return false }
            let spaces = TCWindowSpaceIDs(windowID) ?? []
            if !spaces.isEmpty, spaces.allSatisfy({ TCSpaceType($0.uint64Value) == 0 }),
                let settled = AXWindowAccess.window(withID: windowID, in: application),
                !AXWindowAccess.isFullScreen(settled)
            {
                guard (try? await WindowSummonInventory.contains(target)) == true else {
                    await reportGone(entry)
                    return false
                }
                return true
            }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return false }
        }
        await reportFullScreenFailure(entry,
            detail: "The window didn’t settle in a desktop Space after leaving full screen.")
        return false
    }

    private func reportPartial(_ entry: WindowSwitchEntry, moved: Bool, detail: String) async {
        await core.showNotice(
            title: moved ? "Window Moved" : "Couldn’t Focus Window",
            message: moved
                ? "“\(entry.displayTitle)” moved to this Space, but \(detail)."
                : "“\(entry.displayTitle)” is in this Space, but \(detail).",
            symbol: "macwindow.on.rectangle", tone: .neutral)
    }

    private func reportDestinationFailure() async {
        await core.showNotice(
            title: "Can’t Summon Into This Space",
            message: "Tinycast couldn’t verify a desktop Space here. Switch to one and try again.",
            symbol: "macwindow.on.rectangle", tone: .danger)
    }

    private func reportFullScreenFailure(_ entry: WindowSwitchEntry, detail: String) async {
        await core.showNotice(
            title: "Couldn’t Summon “\(entry.displayTitle)”",
            message: detail, symbol: "macwindow.on.rectangle", tone: .danger)
    }

    private func reportAccessibilityFailure() async {
        let openSettings = await core.reportFailure(
            title: "Tinycast Needs Accessibility Access",
            message: "Summon Window needs access to other apps’ windows.",
            symbol: "macwindow.on.rectangle", recovery: "Open Settings")
        if openSettings { Permissions.openAccessibilitySettings() }
    }

    private func reportScreenRecordingFailure() async {
        let openSettings = await core.reportFailure(
            title: "Tinycast Needs Screen Recording Access",
            message: "Summon Window reads window titles across displays and Spaces.",
            symbol: "macwindow.on.rectangle", recovery: "Open Settings")
        if openSettings { Permissions.openScreenRecordingSettings() }
    }

    private func reportGone(_ entry: WindowSwitchEntry) async {
        await core.showNotice(
            title: "Couldn’t Summon “\(entry.displayTitle)”",
            message: "The window is gone or couldn’t be verified. Search again and retry.",
            symbol: "macwindow.on.rectangle", tone: .danger)
    }

    private func reportMoveFailure(_ entry: WindowSwitchEntry) async {
        await core.showNotice(
            title: "Couldn’t Summon “\(entry.displayTitle)”",
            message: "macOS didn’t move this window to the current Space.",
            symbol: "macwindow.on.rectangle", tone: .danger)
    }
}
