import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
enum WindowSummonInventory {
    private enum ScanError: LocalizedError {
        case unavailable

        var errorDescription: String? { "WindowServer inventory is unavailable." }
    }

    private struct Window: Sendable {
        let windowID: CGWindowID
        let processID: pid_t
        let title: String
        let isMinimized: Bool
        let isFullscreen: Bool
        let spaceIDs: [UInt64]
    }

    struct Target {
        let app: NSRunningApplication
        let windowID: CGWindowID
        let isFullscreen: Bool
    }

    struct Snapshot {
        let entries: [WindowSwitchEntry]
        let targets: [Int: Target]
        let locations: [Int: [WindowSummonLocation]]
    }

    static func contains(_ target: Target) async throws -> Bool {
        guard let belongs = TCWindowBelongsToProcess(target.windowID, target.app.processIdentifier)
        else { throw ScanError.unavailable }
        return belongs.boolValue
    }

    static func snapshot() async throws -> Snapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: false)
        let supplemental = content.windows.map(\.windowID)
        let titles = Dictionary(content.windows.compactMap { window -> (CGWindowID, (pid_t, String))? in
            guard let owner = window.owningApplication, let title = window.title else { return nil }
            return (window.windowID, (owner.processID, title))
        }, uniquingKeysWith: { first, _ in first })
        let running = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first })
        let ownPID = NSRunningApplication.current.processIdentifier
        let eligiblePIDs = Set(running.values.filter {
            $0.processIdentifier != ownPID && !$0.isTerminated && !$0.isHidden
        }.map(\.processIdentifier))
        let ranks = WindowZOrder.appRanks()
        let (windows, screenIDs) = try await Task.detached(priority: .userInitiated) {
            guard let records = TCWindowRecords(supplemental.map { NSNumber(value: $0) }) else {
                throw ScanError.unavailable
            }
            let screenIDs = (TCSpaceDisplayIDs() ?? [:]).reduce(into: [UInt64: UInt32]()) {
                $0[$1.key.uint64Value] = $1.value.uint32Value
            }
            let currentSpaces = Set((TCCurrentSpaceIDs() ?? []).map(\.uint64Value))
            let windows = records.compactMap { record -> Window? in
                guard eligiblePIDs.contains(record.processID), record.parentWindowID == 0,
                    record.alpha > 0, record.tags & (1 << 39) == 0,
                    record.level == 0 || record.isFullscreen
                else { return nil }
                let hasFrame = record.frame.width > 0 && record.frame.height > 0
                guard hasFrame || record.isMinimized, !record.isFullscreen || hasFrame else {
                    return nil
                }
                let captured = titles[record.windowID]
                let caption = (captured?.0 == record.processID ? captured?.1 : nil)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = caption.isEmpty
                    ? record.title.trimmingCharacters(in: .whitespacesAndNewlines) : caption
                guard !title.isEmpty else { return nil }
                let listed = record.spaceIDs.map(\.uint64Value)
                let fallback = listed.isEmpty ? TCWindowSpaceIDs(record.windowID) : nil
                guard !listed.isEmpty || fallback?.isEmpty != true else { return nil }
                let spaceIDs = listed.isEmpty ? fallback?.map(\.uint64Value) ?? [] : listed
                if !record.isOrderedIn && !record.isMinimized,
                    spaceIDs.contains(where: currentSpaces.contains) { return nil }
                return Window(windowID: record.windowID, processID: record.processID,
                    title: title, isMinimized: record.isMinimized,
                    isFullscreen: record.isFullscreen, spaceIDs: spaceIDs)
            }
            return (windows, screenIDs)
        }.value
        var entries: [WindowSwitchEntry] = []
        var targets: [Int: Target] = [:]
        var locations: [Int: [WindowSummonLocation]] = [:]

        for window in windows {
            guard let app = running[window.processID], !app.isTerminated, !app.isHidden else {
                continue
            }
            let handle = entries.count
            let iconURL = app.bundleURL
            entries.append(WindowSwitchEntry(
                handle: handle, appName: app.localizedName ?? app.bundleIdentifier ?? "",
                bundleID: app.bundleIdentifier ?? "",
                iconURL: iconURL, iconStamp: iconURL.map(FileIconStamp.value(for:)) ?? 0,
                title: window.title, isMinimized: window.isMinimized,
                appRank: ranks[window.processID] ?? .max))
            targets[handle] = Target(
                app: app, windowID: window.windowID, isFullscreen: window.isFullscreen)
            locations[handle] = window.spaceIDs.map {
                WindowSummonLocation(spaceID: $0, screenID: screenIDs[$0])
            }.sorted { $0.spaceID < $1.spaceID }
        }
        return Snapshot(entries: entries, targets: targets, locations: locations)
    }
}
