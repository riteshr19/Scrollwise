import SwiftUI
import ScrollwiseCore

/// Mockup 1d, built natively.
///
/// ## About the glass
/// `MenuBarExtra(style: .window)` already presents its content on the system's
/// popover material, which samples the actual desktop behind the menu bar. That
/// is real Liquid Glass and it is why nothing here mixes its own translucent
/// background: layering a hand-made blur on top of a system material is what
/// makes an app look almost-but-not-quite native. There is deliberately no
/// `.glassEffect` call in this file. An earlier version put one on the header
/// tile, but `SymbolTile` fills that exact shape with an opaque gradient, so the
/// material was completely covered — it measured pixel-identical to the same
/// tile with the modifier deleted. Nesting glass inside the popover's own glass
/// would have been the wrong call even if it had rendered.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if state.accessibility.allowsEngine {
                profilePicker
                devicesSection
                Divider().padding(.horizontal, 14)
                appAndLoginSection
                Divider().padding(.horizontal, 14)
                footer
            } else {
                permissionPrompt
                Divider().padding(.horizontal, 14)
                footer
            }
        }
        .frame(width: Metrics.popoverWidth)
        .onAppear { state.refreshDevices() }
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var state = state
        return HStack(spacing: 11) {
            SymbolTile(systemName: "arrow.up.arrow.down", size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.isActive ? "Reversing" : "Not reversing")
                    .font(.headline)
                Text(statusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("Reverse scrolling", isOn: Binding(
                get: { state.settings.isEnabled },
                set: { state.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!state.accessibility.allowsEngine)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var statusDetail: String {
        guard state.accessibility.allowsEngine else { return "Needs Accessibility access" }
        let devices = state.activeAttachedDeviceCount
        let rules = state.enabledAppRuleCount
        let devicePart = switch devices {
        case 0: "Nothing is being reversed"
        case 1: "1 device"
        default: "\(devices) devices"
        }
        guard rules > 0 else { return devicePart }
        return "\(devicePart) · \(rules == 1 ? "1 app rule" : "\(rules) app rules")"
    }

    // MARK: - Sections

    @ViewBuilder
    private var profilePicker: some View {
        if state.settings.profiles.count > 1 {
            Picker("Profile", selection: Binding(
                get: { state.settings.activeProfileID },
                set: { state.setActiveProfile($0) }
            )) {
                ForEach(state.settings.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Devices")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(PointingDeviceType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                deviceRow(for: type)
            }
        }
        .padding(.bottom, 8)
    }

    private func deviceRow(for type: PointingDeviceType) -> some View {
        let rule = state.rule(for: type)
        let attached = state.devices(ofType: type)
        // Name the hardware when exactly one of this class is present; otherwise
        // name the class, because the rule genuinely governs all of them.
        let label = attached.count == 1 ? attached[0].name : type.displayName

        return HStack(spacing: 10) {
            Image(systemName: symbol(for: type))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.body)
                    // Absent hardware is dimmed with a semantic style, never by
                    // stacking opacity on top of one — `.tertiary` at 50 % opacity
                    // measured 1.33:1 against the popover, which is unreadable.
                    .foregroundStyle(attached.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                if attached.count > 1 {
                    Text("\(attached.count) connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if attached.isEmpty {
                Text("Not connected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Reverse \(label)", isOn: Binding(
                    get: { rule.reverseVertical },
                    set: { newValue in
                        var updated = rule
                        updated.reverseVertical = newValue
                        state.setRule(updated)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!state.settings.isEnabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func symbol(for type: PointingDeviceType) -> String {
        switch type {
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .mouse: "computermouse"
        case .tablet: "pencil.tip"
        case .unknown: "questionmark.circle"
        }
    }

    private var appAndLoginSection: some View {
        VStack(spacing: 0) {
            if let frontmost = state.frontmostApp {
                Toggle(isOn: Binding(
                    get: { state.frontmostAppRule?.action == .passthrough },
                    set: { state.setSkipFrontmostApp($0) }
                )) {
                    HStack(spacing: 4) {
                        Text("Skip in this app")
                        Text("— \(frontmost.name)").foregroundStyle(.secondary)
                    }
                    // The label must be the thing that expands. Putting
                    // `maxWidth: .infinity` on the Toggle instead just centres
                    // the label-and-switch pair inside the wider row.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Skip scroll reversing in \(frontmost.name)")
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            Button {
                openSettings(selecting: .apps)
            } label: {
                HStack {
                    Text("All app rules")
                    Spacer()
                    Text("\(state.settings.appRules.count)").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Toggle(isOn: Binding(
                get: { state.settings.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            )) {
                Text("Start at login")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!state.launchAtLoginAvailable)
            // Wrapping the label in a `.frame` to push the switch to the trailing
            // edge stops SwiftUI treating that text as the control's label, so
            // the checkbox reaches VoiceOver unnamed unless it is restored here.
            .accessibilityLabel("Start at login")
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 4)
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scrollwise needs Accessibility access before it can change scrolling.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Accessibility Settings…") {
                state.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Toggle").font(.callout).foregroundStyle(.secondary)
            KeyCapGroup(keys: ["⌥", "⌘", "R"])

            Spacer(minLength: 8)

            Button("Settings…") { openSettings(selecting: .scrolling) }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func openSettings(selecting pane: SettingsPane) {
        SettingsWindowPresenter.shared.show(pane: pane)
    }
}

/// The ⌥⌘R chips in the footer.
struct KeyCapGroup: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.caption.monospaced())
                    .frame(minWidth: 18, minHeight: 18)
                    .background(.background.secondary, in: .rect(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, lineWidth: 0.5)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Option Command R")
    }
}
