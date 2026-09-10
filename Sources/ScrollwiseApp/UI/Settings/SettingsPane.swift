import SwiftUI

/// The sidebar items from mockup 1b.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case scrolling, devices, apps, profiles, shortcuts, general, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scrolling: "Scrolling"
        case .devices: "Devices"
        case .apps: "Apps"
        case .profiles: "Profiles"
        case .shortcuts: "Shortcuts"
        case .general: "General"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .scrolling: "arrow.up.arrow.down"
        case .devices: "computermouse"
        case .apps: "square.grid.2x2"
        case .profiles: "person.crop.circle"
        case .shortcuts: "command"
        case .general: "gearshape"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .scrolling: .blue
        case .devices: .gray
        case .apps: .orange
        case .profiles: .purple
        case .shortcuts: .green
        case .general, .about: .secondary
        }
    }

    /// The visual break between feature panes and app-level panes in 1b.
    static let featurePanes: [SettingsPane] = [.scrolling, .devices, .apps, .profiles, .shortcuts]
    static let appPanes: [SettingsPane] = [.general, .about]
}
