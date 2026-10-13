import Foundation

@MainActor
@Observable
final class WindowSummonSession {
    private(set) var snapshot: [WindowSwitchEntry] = []
    private(set) var filtered: [WindowSwitchEntry] = []
    private(set) var isLoading = false
    private(set) var hasStarted = false
    private(set) var locations: [Int: [WindowSummonLocation]] = [:]

    var labels: [Int: String] {
        locations.mapValues(WindowSummonLocation.summary)
    }

    var currentHandles: Set<Int> {
        guard currentSpaceID != 0 else { return [] }
        return Set(locations.compactMap { handle, places in
            places.contains { $0.spaceID == currentSpaceID } ? handle : nil
        })
    }

    private var query = ""
    private var currentSpaceID: UInt64 = 0
    @ObservationIgnored private var targets: [Int: WindowSummonInventory.Target] = [:]
    @ObservationIgnored private var scan: Task<Void, Never>?

    func begin() {
        reset()
        hasStarted = true
        isLoading = true
    }

    func retain(_ task: Task<Void, Never>) { scan = task }

    func present(_ snapshot: WindowSummonInventory.Snapshot) {
        self.snapshot = WindowSwitchOrder.sorted(snapshot.entries)
        targets = snapshot.targets
        locations = snapshot.locations
        isLoading = false
        scan = nil
        applyQuery()
    }

    func fail() {
        isLoading = false
        scan = nil
    }

    func target(for handle: Int) -> WindowSummonInventory.Target? { targets[handle] }

    func destination(_ spaceID: UInt64) {
        guard currentSpaceID != spaceID else { return }
        currentSpaceID = spaceID
        applyQuery()
    }

    func reset() {
        scan?.cancel()
        scan = nil
        snapshot = []
        filtered = []
        targets = [:]
        locations = [:]
        currentSpaceID = 0
        query = ""
        isLoading = false
        hasStarted = false
    }

    func filter(_ query: String) {
        self.query = query
        applyQuery()
    }

    private func applyQuery() {
        filtered = WindowSummonOrder.rank(
            snapshot, locations: locations, currentSpaceID: currentSpaceID,
            for: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
