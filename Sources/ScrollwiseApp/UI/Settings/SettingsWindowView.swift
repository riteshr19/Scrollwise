import SwiftUI
import ScrollwiseCore

/// Mockup 1b, built natively.
///
/// ## About the glass
/// `NavigationSplitView` gives its sidebar the system's sidebar material — the
/// same one Finder, Mail and System Settings use, which samples the desktop
/// behind the window. That is what the mockup was approximating with
/// `rgba(255,255,255,.28)` plus a 60px blur, and the real thing is both more
/// accurate and free. No custom background is applied to the sidebar for exactly
/// that reason.
struct SettingsWindowView: View {
    @Environment(AppState.self) private var state
    @State private var selection: SettingsPane

    init(initialPane: SettingsPane = .scrolling) {
        _selection = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarMinWidth,
                    ideal: Metrics.sidebarIdealWidth,
                    max: 260
                )
        } detail: {
            detail
                .frame(minWidth: Metrics.detailMinWidth)
        }
        .frame(minHeight: Metrics.windowMinHeight)
        .onAppear { state.refreshDevices() }
        .onChange(of: selection) { _, new in
            if new == .devices { state.refreshDevices() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(SettingsPane.featurePanes) { pane in
                    row(for: pane)
                }
            }
            Section {
                ForEach(SettingsPane.appPanes) { pane in
                    row(for: pane)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            statusFooter
        }
    }

    private func row(for pane: SettingsPane) -> some View {
        Label {
            Text(pane.title)
        } icon: {
            SymbolTile(systemName: pane.symbol, tint: pane.tint)
        }
        .tag(pane)
    }

    /// The "Version … · Accessibility granted" line from the mockup — kept
    /// truthful in both halves: the version comes from the bundle, and the
    /// permission text reports what the system actually reports, not what we hope.
    private var statusFooter: some View {
        HStack(spacing: 5) {
            Image(systemName: state.accessibility.allowsEngine
                  ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(state.accessibility.allowsEngine ? .green : .orange)
            Text(accessibilityWording)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var accessibilityWording: String {
        switch state.accessibility {
        case .granted: "Version \(AppInfo.version) · Accessibility granted"
        case .denied: "Version \(AppInfo.version) · Accessibility needed"
        case .grantedButTapFailed: "Version \(AppInfo.version) · Access not working"
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .scrolling: ScrollingPane()
        case .devices: DevicesPane()
        case .apps: AppsPane()
        case .profiles: ProfilesPane()
        case .shortcuts: ShortcutsPane()
        case .general: GeneralPane()
        case .about: AboutPane()
        }
    }
}

/// Shared chrome for every detail pane: title bar, permission banner, content.
struct PaneScaffold<Content: View>: View {
    @Environment(AppState.self) private var state
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                if !state.accessibility.allowsEngine {
                    permissionBanner
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .toolbar { ProfileToolbarItem() }
    }

    private var permissionBanner: some View {
        StatusBanner(
            title: bannerTitle,
            message: bannerMessage,
            actionTitle: "Open Settings…",
            action: { state.openAccessibilitySettings() }
        )
    }

    private var bannerTitle: String {
        state.accessibility == .grantedButTapFailed
            ? "Accessibility access is not working"
            : "Accessibility access required"
    }

    private var bannerMessage: String {
        switch state.accessibility {
        case .grantedButTapFailed:
            "macOS reports access as granted but will not let Scrollwise read scroll events. Remove it from the Accessibility list and add it again."
        default:
            "Until this is granted, these settings are saved but no scrolling is changed."
        }
    }
}

/// The profile popup in the pane's toolbar, matching 1b.
struct ProfileToolbarItem: ToolbarContent {
    @Environment(AppState.self) private var state

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Profile", selection: Binding(
                get: { state.settings.activeProfileID },
                set: { state.setActiveProfile($0) }
            )) {
                ForEach(state.settings.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(state.settings.profiles.count < 2)
        }
    }
}

enum AppInfo {
    static var version: String {
        // Deliberately not a plausible-looking version. A fallback that mirrors
        // the current one is a second source of truth: it goes stale on the next
        // bump and then reports a version the bundle does not have.
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }
}
