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
        if !TCWindowIsInSpace(windowID, spaceID) {
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
        let application = AXWindowAccess.application(for: target.app.processIdentifier)
        var found: AXUIElement?
        for _ in 0..<4 {
            found = AXWindowAccess.window(withID: windowID, in: application)
            if found != nil { break }
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard let window = found else {
            await reportPartial(entry, detail: "Tinycast couldn’t find its Accessibility window")
            return
        }
        if AXWindowAccess.bool(window, kAXMinimizedAttribute) == true {
            _ = AXWindowAccess.unminimize(window)
        }
        guard let frame = AXWindowAccess.frame(of: window) else {
            await reportPartial(entry, detail: "its position couldn’t be verified")
            return
        }
        if !canvas.contains(frame) {
            let landing = WindowPlacementEngine.clamped(frame, into: canvas)
            guard AXWindowAccess.setPosition(landing.origin, on: window) else {
                await reportPartial(entry, detail: "it couldn’t be placed on this display")
                return
            }
        }
        guard let placed = AXWindowAccess.frame(of: window), placed.intersects(canvas) else {
            await reportPartial(entry, detail: "its display position couldn’t be verified")
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
        await reportPartial(entry, detail: "Tinycast couldn’t confirm focus")
    }

    private func reportPartial(_ entry: WindowSwitchEntry, detail: String) async {
        await core.showNotice(
            title: "Window Moved",
            message: "“\(entry.displayTitle)” moved to this Space, but \(detail).",
            symbol: "macwindow.on.rectangle", tone: .neutral)
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
