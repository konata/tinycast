import Foundation

struct WindowSummonLocation: Hashable, Sendable {
    let spaceID: UInt64
    let screenID: UInt32?

    var label: String { "\(spaceID) @ \(screenID.map(String.init) ?? "?")" }

    static func summary(_ locations: [Self]) -> String {
        locations.isEmpty ? "? @ ?" : locations.map(\.label).joined(separator: ", ")
    }
}

enum WindowSummonOrder {
    static func rank(
        _ entries: [WindowSwitchEntry], locations: [Int: [WindowSummonLocation]],
        currentSpaceID: UInt64, for query: String
    ) -> [WindowSwitchEntry] {
        var remote: [WindowSwitchEntry] = []
        var unknown: [WindowSwitchEntry] = []
        var current: [WindowSwitchEntry] = []
        for entry in entries {
            guard let places = locations[entry.handle], !places.isEmpty else {
                unknown.append(entry)
                continue
            }
            if places.contains(where: { $0.spaceID == currentSpaceID }) {
                current.append(entry)
            } else {
                remote.append(entry)
            }
        }
        return Array((
            WindowSwitchQuery.rank(remote, for: query)
                + WindowSwitchQuery.rank(unknown, for: query)
                + WindowSwitchQuery.rank(current, for: query)
        ).prefix(WindowSwitchQuery.resultLimit))
    }
}
