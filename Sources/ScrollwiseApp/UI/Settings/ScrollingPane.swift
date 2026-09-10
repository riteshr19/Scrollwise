import SwiftUI
import ScrollwiseCore

/// The master switch and per-axis behaviour — the pane from mockup 1a/1b.
struct ScrollingPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        PaneScaffold(title: "Scrolling") {
            masterCard
            axesSection
            summarySection
        }
    }

    private var masterCard: some View {
        HStack(spacing: 14) {
            SymbolTile(systemName: "arrow.up.arrow.down", size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Reverse scrolling").font(.title3.weight(.semibold))
                Text(state.isActive ? activeSummary : inactiveReason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle("Reverse scrolling", isOn: Binding(
                get: { state.settings.isEnabled },
                set: { state.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!state.accessibility.allowsEngine)
        }
        .padding(16)
        .background(Color.accentColor.opacity(state.isActive ? 0.10 : 0.0), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(state.isActive ? AnyShapeStyle(Color.accentColor.opacity(0.3)) : AnyShapeStyle(.separator), lineWidth: 0.5)
        }
        .animation(.smooth(duration: 0.25), value: state.isActive)
    }

    private var activeSummary: String {
        let devices = state.activeDeviceCount
        let rules = state.enabledAppRuleCount
        let devicePart = "Active on \(devices) of \(PointingDeviceType.allCases.count - 1) device types"
        return rules > 0 ? "\(devicePart) · \(rules) app rules" : devicePart
    }

    private var inactiveReason: String {
        if !state.accessibility.allowsEngine { return "Waiting for Accessibility access" }
        if !state.settings.isEnabled { return "Switched off" }
        if !state.isEngineRunning { return "Reconnecting to the event stream…" }
        return "No device is set to reverse"
    }

    // MARK: - Axes

    private var axesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionCaption(text: "Axes")
            SettingsCard {
                axisRow(
                    title: "Vertical",
                    subtitle: nil,
                    isOn: axisBinding(vertical: true)
                )
                RowDivider()
                axisRow(
                    title: "Horizontal",
                    subtitle: "Off by default — reversing it also flips timelines and canvases",
                    isOn: axisBinding(vertical: false)
                )
            }
        }
    }

    private func axisRow(title: String, subtitle: String?, isOn: Binding<Bool>) -> some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!state.settings.isEnabled || !state.accessibility.allowsEngine)
        }
    }

    /// Axis switches here act on every device class at once, which is what the
    /// mockup's single pair of switches implies. Per-device overrides live in the
    /// Devices pane.
    private func axisBinding(vertical: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let rules = state.settings.activeProfile.deviceRules
                return rules.contains { vertical ? $0.reverseVertical : $0.reverseHorizontal }
            },
            set: { newValue in
                for var rule in state.settings.activeProfile.deviceRules {
                    // Only touch classes that are actually participating, so
                    // switching an axis on cannot silently enable a class the
                    // user had turned off.
                    guard rule.isEnabled else { continue }
                    if vertical { rule.reverseVertical = newValue }
                    else { rule.reverseHorizontal = newValue }
                    state.setRule(rule)
                }
            }
        )
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionCaption(text: "Right now")
            SettingsCard {
                SettingsRow(
                    title: "Engine",
                    subtitle: state.isEngineRunning
                        ? "Attached to the scroll event stream"
                        : "Not attached",
                    systemImage: state.isEngineRunning ? "bolt.fill" : "bolt.slash"
                ) {
                    Text(state.isEngineRunning ? "Running" : "Stopped")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let frontmost = state.frontmostApp {
                    RowDivider()
                    SettingsRow(
                        title: "Frontmost app",
                        subtitle: state.frontmostAppRule.map { "Rule: \($0.action.displayName)" }
                            ?? "No rule — device settings apply",
                        systemImage: "macwindow"
                    ) {
                        Text(frontmost.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
