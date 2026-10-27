import Foundation

@main
@MainActor
struct WindowSwitchTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func entry(
        _ handle: Int, app: String = "Safari", title: String = "Window",
        minimized: Bool = false, rank: Int = 0
    ) -> WindowSwitchEntry {
        WindowSwitchEntry(
            handle: handle, appName: app, bundleID: "com.example.\(app.lowercased())",
            iconURL: nil, iconStamp: 0, title: title, isMinimized: minimized, appRank: rank)
    }

    static func main() {
        identity()
        displayTitle()
        searchMapping()
        ordering()
        orderingIsTotal()
        switchable()
        ranking()
        rankingLimit()
        summonLocations()
        summonOrdering()
        summonRankingLimit()

        print(failures == 0 ? "Window switch tests passed" : "\(failures) window switch tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func identity() {
        expect(entry(7).id == "7", "the id is the handle, which is unique inside one sweep")
    }

    static func displayTitle() {
        expect(entry(0, title: "Notes.md").displayTitle == "Notes.md", "a titled window shows it")
        expect(
            entry(0, app: "Preview", title: "").displayTitle == "Preview",
            "an untitled window reads as its app rather than as a blank row")
        expect(
            entry(0, app: "Preview", title: "   ").displayTitle == "Preview",
            "a whitespace-only title is no title")
    }

    static func searchMapping() {
        let aliases = entry(0, app: "Safari", title: "Inbox").searchFields().aliases
        expect(
            aliases.contains { $0.text == "Inbox" && $0.role == .name },
            "the window title is the name a query matches")
        expect(
            aliases.contains { $0.text == "Safari" && $0.role == .owner },
            "the app rides as owner: every window of one app shares it")
    }

    static func ordering() {
        let sorted = WindowSwitchOrder.sorted([
            entry(0, app: "Mail", rank: 2),
            entry(1, app: "Safari", minimized: true, rank: 0),
            entry(2, app: "Safari", rank: 0),
            entry(3, app: "Safari", rank: 0),
            entry(4, app: "Zed", rank: .max)
        ])
        expect(
            sorted.map(\.handle) == [2, 3, 0, 4, 1],
            "front app first, then by rank, unranked next, minimized last: \(sorted.map(\.handle))")
    }

    static func orderingIsTotal() {
        let entries = (0..<12).map {
            entry($0, app: ["Mail", "Safari", "Zed"][$0 % 3], minimized: $0 % 4 == 0, rank: $0 % 3)
        }
        let once = WindowSwitchOrder.sorted(entries)
        let twice = WindowSwitchOrder.sorted(entries.reversed())
        expect(
            once.map(\.handle) == twice.map(\.handle),
            "the order is total, so a shuffled sweep sorts identically")
        expect(
            once.map(\.handle).sorted() == entries.map(\.handle).sorted(),
            "sorting drops nothing")
        let split = once.firstIndex(where: \.isMinimized) ?? once.count
        expect(
            once[split...].allSatisfy(\.isMinimized),
            "minimized windows form one run at the end, never interleaved")
    }

    static func switchable() {
        expect(
            WindowSwitchPolicy.isSwitchable(
                isStandardWindow: true, isMinimized: false, canMinimize: true),
            "a standard window is offered")
        expect(
            WindowSwitchPolicy.isSwitchable(
                isStandardWindow: true, isMinimized: true, canMinimize: true),
            "a minimized window that still reports its subrole is offered")
        expect(
            WindowSwitchPolicy.isSwitchable(
                isStandardWindow: false, isMinimized: true, canMinimize: true),
            "a minimized window reading AXDialog is offered, which is Finder and Transmission")
        expect(
            !WindowSwitchPolicy.isSwitchable(
                isStandardWindow: false, isMinimized: false, canMinimize: true),
            "a sheet is no window to switch to")
        expect(
            !WindowSwitchPolicy.isSwitchable(
                isStandardWindow: false, isMinimized: true, canMinimize: false),
            "a dialog cannot minimize, so it is never read as a minimized window")
    }

    static func ranking() {
        let entries = [
            entry(0, app: "Mail", title: "Drafts"),
            entry(1, app: "Safari", title: "Inbox"),
            entry(2, app: "Safari", title: "Inbox archive")
        ]
        expect(
            WindowSwitchQuery.rank(entries, for: "").map(\.handle) == [0, 1, 2],
            "an empty query keeps the order it was handed")
        expect(
            WindowSwitchQuery.rank(entries, for: "Inbox").first?.handle == 1,
            "the exact title beats the one that only starts with it")
        expect(
            WindowSwitchQuery.rank(entries, for: "Safari").map(\.handle) == [1, 2],
            "the app name matches every one of its windows, in the order given")
        expect(
            WindowSwitchQuery.rank(entries, for: "zzz").isEmpty,
            "a query nothing matches ranks nothing")
    }

    static func rankingLimit() {
        let entries = (0..<(WindowSwitchQuery.resultLimit + 50)).map {
            entry($0, app: "Safari", title: "Tab \($0)")
        }
        expect(
            WindowSwitchQuery.rank(entries, for: "").count == WindowSwitchQuery.resultLimit,
            "an empty query is capped too, so a huge sweep never builds a huge list")
        expect(
            WindowSwitchQuery.rank(entries, for: "Tab").count == WindowSwitchQuery.resultLimit,
            "the cap holds under a query every row matches")
    }

    static func summonLocations() {
        expect(
            WindowSummonLocation(spaceID: 5, screenID: 2).label == "5 @ 2",
            "Summon Window shows the raw Space and display IDs")
        expect(
            WindowSummonLocation(spaceID: 5, screenID: nil).label == "5 @ ?",
            "an unmapped display is not guessed from window geometry")
        expect(
            WindowSummonLocation.summary([]) == "? @ ?",
            "a window without reported Space membership remains labeled")
        expect(
            WindowSummonLocation.summary([
                WindowSummonLocation(spaceID: 5, screenID: 2),
                WindowSummonLocation(spaceID: 6, screenID: 2)
            ]) == "5 @ 2, 6 @ 2",
            "a window in several Spaces shows every reported location")
    }

    static func summonOrdering() {
        let current = WindowSummonLocation(spaceID: 6, screenID: 2)
        let remote = WindowSummonLocation(spaceID: 5, screenID: 2)
        let secondDisplay = WindowSummonLocation(spaceID: 10, screenID: 3)
        let locations = [0: [current], 1: [remote], 2: [], 3: [secondDisplay, current]]
        let entries = [
            entry(0, title: "Inbox"), entry(2, title: "Inbox hidden"),
            entry(1, title: "Inbox archive"), entry(3, title: "Inbox shared")
        ]
        expect(
            WindowSummonOrder.rank(entries, locations: locations, currentSpaceID: 6, for: "")
                .map(\.handle) == [1, 2, 0, 3],
            "remote windows precede unknown locations and every current-Space window")
        expect(
            WindowSummonOrder.rank(entries, locations: locations, currentSpaceID: 6, for: "Inbox")
                .map(\.handle) == [1, 2, 0, 3],
            "a stronger current-Space title match still remains after remote matches")
        expect(
            WindowSummonOrder.rank(entries, locations: locations, currentSpaceID: 10, for: "")
                .map(\.handle) == [0, 1, 2, 3],
            "moving the palette to another display changes which Space is last")
    }

    static func summonRankingLimit() {
        let entries = (0...WindowSwitchQuery.resultLimit).map { entry($0, title: "Tab") }
        let locations = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.handle, [WindowSummonLocation(spaceID: $0.handle == 0 ? 6 : 5, screenID: 2)])
        })
        let ranked = WindowSummonOrder.rank(entries, locations: locations, currentSpaceID: 6, for: "Tab")
        expect(
            ranked.count == WindowSwitchQuery.resultLimit && !ranked.contains { $0.handle == 0 },
            "the 200-row cap keeps remote windows before the current Space")
    }
}
