import SwiftUI
import ScrollwiseCore

/// Profiles — named sets of device rules, switchable from the popover.
struct ProfilesPane: View {
    @Environment(AppState.self) private var state
    @State private var newProfileName = ""

    var body: some View {
        PaneScaffold(
            title: "Profiles",
            subtitle: "Keep separate sets of device rules and switch between them from the menu bar."
        ) {
            SettingsCard {
                ForEach(Array(state.settings.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { RowDivider() }
                    SettingsRow(
                        title: profile.name,
                        subtitle: summary(for: profile),
                        systemImage: profile.id == state.settings.activeProfileID
                            ? "checkmark.circle.fill" : "circle"
                    ) {
                        HStack(spacing: 10) {
                            if profile.id != state.settings.activeProfileID {
                                Button("Use") { state.setActiveProfile(profile.id) }
                                    .controlSize(.small)
                            }
                            Button {
                                state.removeProfile(profile.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .disabled(state.settings.profiles.count < 2)
                            .help(state.settings.profiles.count < 2
                                  ? "The last profile cannot be removed"
                                  : "Remove this profile")
                            .accessibilityLabel("Remove \(profile.name)")
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("New profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit(addProfile)
                Button("Add", action: addProfile)
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    private var trimmedName: String {
        newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addProfile() {
        guard !trimmedName.isEmpty else { return }
        state.addProfile(named: trimmedName)
        newProfileName = ""
    }

    private func summary(for profile: Profile) -> String {
        let reversed = profile.deviceRules
            .filter { $0.isEnabled && $0.reverseVertical }
            .map(\.device.displayName)
        return reversed.isEmpty ? "Nothing reversed" : "Reverses \(reversed.joined(separator: ", "))"
    }
}

/// Shortcuts. The global toggle is registered by `GlobalShortcutService`.
struct ShortcutsPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        PaneScaffold(
            title: "Shortcuts",
            subtitle: "One shortcut, always available, so scrolling can be flipped without opening anything."
        ) {
            SettingsCard {
                SettingsRow(
                    title: "Toggle from anywhere",
                    subtitle: state.isShortcutRegistered
                        ? "Flips the master switch without opening the app"
                        : "Unavailable — another app already uses this combination",
                    systemImage: "command",
                    isDimmed: !state.isShortcutRegistered
                ) {
                    KeyCapGroup(keys: ["⌥", "⌘", "R"])
                }
            }
            Text("The shortcut is fixed in this version. It is registered with the system only while Scrollwise is running.")
                .font(.caption)
                // Prose the user is meant to read: `.secondary`, not `.tertiary`.
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GeneralPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        PaneScaffold(title: "General") {
            SettingsCard {
                SettingsRow(
                    title: "Start at login",
                    subtitle: launchAtLoginSubtitle,
                    systemImage: "power"
                ) {
                    Toggle("Start at login", isOn: Binding(
                        get: { state.settings.launchAtLogin },
                        set: { state.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!state.launchAtLoginAvailable)
                }
                if state.launchAtLoginNeedsApproval {
                    RowDivider()
                    SettingsRow(title: "Approve in System Settings") {
                        Button("Open Login Items…") { state.openLoginItemsSettings() }
                            .controlSize(.small)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionCaption(text: "Accessibility access")
                SettingsCard {
                    SettingsRow(
                        title: "Status",
                        subtitle: accessibilityDetail,
                        systemImage: state.accessibility.allowsEngine
                            ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                    ) {
                        Button("Open Settings…") { state.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var launchAtLoginSubtitle: String {
        if let refusal = state.launchAtLoginRefusal {
            return "Unavailable — \(refusal)"
        }
        if state.launchAtLoginNeedsApproval {
            return "Waiting for approval in System Settings › General › Login Items"
        }
        return "Opens silently in the menu bar"
    }

    private var accessibilityDetail: String {
        switch state.accessibility {
        case .granted: "Granted — scroll events can be read and changed"
        case .denied: "Not granted — settings are saved but nothing is changed"
        case .grantedButTapFailed: "Listed as granted, but the connection is being refused"
        }
    }
}

/// Where the project identifies itself. Everything asserted here is checked:
/// the version comes from the bundle, and the privacy claims correspond to an
/// app that links no networking, requests no entitlement beyond disabling Apple
/// events, and has no third-party dependencies.
struct AboutPane: View {

    private static let repository = URL(string: "https://github.com/riteshr19/Scrollwise")!
    private static let licence = URL(string: "https://github.com/riteshr19/Scrollwise/blob/main/LICENSE")!
    private static let email = URL(string: "mailto:contact@riteshrana.engineer")!

    var body: some View {
        PaneScaffold(title: "About") {
            identity
            madeBy
            source
            privacy
        }
    }

    // MARK: - Identity

    private var identity: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    SymbolTile(systemName: "arrow.up.arrow.down", size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scrollwise").font(.title2.weight(.semibold))
                        Text("Version \(AppInfo.version) (\(AppInfo.build))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Reverses the direction of scrolling, with separate settings for trackpads, mice and tablets.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    // MARK: - Made by

    private var madeBy: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionCaption(text: "Made by")
            SettingsCard {
                SettingsRow(title: "Ritesh Rana", subtitle: "contact@riteshrana.engineer") {
                    Link(destination: Self.email) {
                        Label("Email", systemImage: "envelope")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Email Ritesh Rana at contact@riteshrana.engineer")
                }
            }
        }
    }

    // MARK: - Source

    private var source: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionCaption(text: "Source")
            SettingsCard {
                SettingsRow(title: "Repository", subtitle: "github.com/riteshr19/Scrollwise") {
                    Link(destination: Self.repository) {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Open the Scrollwise repository on GitHub")
                }
                RowDivider()
                SettingsRow(title: "Licence", subtitle: "MIT — free to use, modify and redistribute") {
                    Link(destination: Self.licence) {
                        Label("Read", systemImage: "doc.text")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Read the MIT licence")
                }
            }
        }
    }

    // MARK: - Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionCaption(text: "Privacy")
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    privacyLine("wifi.slash", "No network access. The app links no networking code and requests no network entitlement.")
                    privacyLine("chart.bar.xaxis", "No analytics, no telemetry, no crash reporting. Nothing is collected or sent.")
                    privacyLine("cursorarrow.motionlines", "Scroll events are read to reverse them and for nothing else. Keystrokes, clicks and pointer movement are never inspected.")
                    privacyLine("shippingbox", "No third-party code. Apple frameworks only.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private func privacyLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
