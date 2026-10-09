import Foundation

@MainActor
@Observable
final class WindowSummonSession {
    private(set) var snapshot: [WindowSwitchEntry] = []
    private(set) var filtered: [WindowSwitchEntry] = []
    private(set) var isLoading = false
    private(set) var hasStarted = false

    private var query = ""
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
        isLoading = false
        scan = nil
        applyQuery()
    }

    func fail() {
        isLoading = false
        scan = nil
    }

    func target(for handle: Int) -> WindowSummonInventory.Target? { targets[handle] }

    func reset() {
        scan?.cancel()
        scan = nil
        snapshot = []
        filtered = []
        targets = [:]
        query = ""
        isLoading = false
        hasStarted = false
    }

    func filter(_ query: String) {
        self.query = query
        applyQuery()
    }

    private func applyQuery() {
        filtered = WindowSwitchQuery.rank(
            snapshot, for: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
