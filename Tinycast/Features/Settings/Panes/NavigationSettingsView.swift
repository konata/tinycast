import SwiftUI

/// Window navigation, retrieval and menu search share one switch.
struct NavigationSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.navigationEnabled) {
                    SettingsRowTitle(.navigationNavigation, "Enable navigation")
                    Text("Switch to a window, summon one here, or search menu bar items.")
                }
            } header: {
                SettingsSectionHeader(.navigationNavigation)
            }

            // No "show in launcher" switch: the per-command checkboxes below already are one.
            FeatureCommandsSection(
                owner: .navigation, anchor: .navigationCommands,
                excluding: [.searchMenuItems]
            )
            .settingsEnabled(settings.navigationEnabled)

            // The menu-search command sits with the two settings that only it reads.
            Section {
                if let entry = CommandCatalog.entry(for: .searchMenuItems) {
                    FeatureCommandRow(entry: entry)
                }

                Toggle(isOn: $settings.menuSearchShowsAppleMenu) {
                    SettingsRowTitle(.navigationMenuSearch, "Show Apple menu items")
                    Text("Include the Apple menu, which is the same under every application.")
                }

                SettingsRow(
                    title: "Disabled Applications",
                    subtitle:
                        "Search Menu Bar Items will not show menu items from these applications.",
                    anchor: .navigationMenuSearch
                ) {
                    EmptyView()
                }

                DisabledApplicationsList(bundleIDs: $settings.menuSearchDisabledApps)
            } header: {
                SettingsSectionHeader(.navigationMenuSearch)
            }
            .settingsEnabled(settings.navigationEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.navigation)
    }
}
