import SwiftUI

struct WindowSwitchList: View {

    @Environment(\.metrics) private var metrics
    let entries: [WindowSwitchEntry]
    let selectedID: WindowSwitchEntry.ID?
    let scroll: ScrollIntent
    let onActivate: (WindowSwitchEntry) -> Void
    var places: [Int: String] = [:]
    var currentHandles: Set<Int> = []

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == entries.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        WindowSwitchRow(
                            entry: entry, selected: entry.id == selectedID,
                            place: places[entry.handle], current: currentHandles.contains(entry.handle))
                            .selectionFrame(entry.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(entry) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct WindowSwitchRow: View {

    @Environment(\.metrics) private var metrics
    let entry: WindowSwitchEntry
    let selected: Bool
    let place: String?
    let current: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var titleStyle: AnyShapeStyle {
        if current { return AnyShapeStyle(Theme.Colors.currentSpaceTitle) }
        return entry.isMinimized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    private var owner: String {
        entry.isMinimized ? "\(entry.appName) · Minimized" : entry.appName
    }

    private var trailing: String { place.map { "\(owner) · \($0)" } ?? owner }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let iconURL = entry.iconURL {
                    EntryIconView(source: .file(stamp: entry.iconStamp), fileURL: iconURL)
                } else {
                    EntryIconView(source: .symbol("macwindow"))
                }
            }
            .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            .opacity(entry.isMinimized ? 0.5 : 1)
            Text(entry.displayTitle)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(titleStyle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: metrics.spacing.md)
            HStack(spacing: metrics.spacing.sm) {
                Text(owner)
                    .lineLimit(1)
                if let place {
                    Text(place)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.displayTitle)
        .accessibilityValue(trailing)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
