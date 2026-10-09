import Foundation

/// One window row shared by Switch Windows and Summon Window; platform handles stay elsewhere.
struct WindowSwitchEntry: Identifiable, Hashable, Sendable {
    /// A session-local index into the selected screen's live targets.
    let handle: Int
    let appName: String
    let bundleID: String
    let iconURL: URL?
    let iconStamp: Int
    let title: String
    let isMinimized: Bool
    /// Lower is nearer the front; `.max` when the app has no on-screen window to rank it by.
    let appRank: Int

    /// A string, because every palette list identifies its rows by one.
    var id: String { String(handle) }

    /// A document window with no title yet reads as its app rather than as a blank row.
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? appName : title
    }

    // The app name rides as owner, not as a name: every window of one app shares it.
    func searchFields() -> SearchFields {
        [SearchAlias.name(displayTitle), SearchAlias.owner(appName)]
    }
}
