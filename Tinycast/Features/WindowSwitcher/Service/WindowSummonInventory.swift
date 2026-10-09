import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
enum WindowSummonInventory {
    struct Target {
        let app: NSRunningApplication
        let windowID: CGWindowID
    }

    struct Snapshot {
        let entries: [WindowSwitchEntry]
        let targets: [Int: Target]
        let locations: [Int: [WindowSummonLocation]]
    }

    static func contains(_ target: Target) async throws -> Bool {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: false)
        return content.windows.contains {
            $0.windowID == target.windowID
                && $0.owningApplication?.processID == target.app.processIdentifier
        }
    }

    static func snapshot() async throws -> Snapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: false)
        let running = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first })
        let ownPID = NSRunningApplication.current.processIdentifier
        let ranks = WindowZOrder.appRanks()
        let screenIDs = TCSpaceDisplayIDs() ?? [:]
        var entries: [WindowSwitchEntry] = []
        var targets: [Int: Target] = [:]
        var locations: [Int: [WindowSummonLocation]] = [:]

        for window in content.windows {
            guard window.windowLayer == 0, window.frame.width > 0, window.frame.height > 0,
                let owner = window.owningApplication, owner.processID != ownPID,
                let app = running[owner.processID], !app.isTerminated,
                let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty
            else { continue }

            let handle = entries.count
            let iconURL = app.bundleURL
            entries.append(WindowSwitchEntry(
                handle: handle, appName: app.localizedName ?? owner.applicationName,
                bundleID: app.bundleIdentifier ?? owner.bundleIdentifier,
                iconURL: iconURL, iconStamp: iconURL.map(FileIconStamp.value(for:)) ?? 0,
                title: title, isMinimized: false, appRank: ranks[owner.processID] ?? .max))
            targets[handle] = Target(app: app, windowID: window.windowID)
            locations[handle] = (TCWindowSpaceIDs(window.windowID) ?? []).map {
                WindowSummonLocation(spaceID: $0.uint64Value, screenID: screenIDs[$0]?.uint32Value)
            }.sorted { $0.spaceID < $1.spaceID }
        }
        return Snapshot(entries: entries, targets: targets, locations: locations)
    }
}
