import SwiftUI
import ScrollwiseCore

/// Mockup 1b's Devices list.
///
/// Presents one row per device *class*, naming the attached hardware underneath
/// it. The mockup showed one row per physical device with its own switch; that
/// is not implementable, because scroll events reaching an event tap carry no
/// device identifier (see `PointingDeviceType`). Rather than show per-device
/// switches that secretly all move together, the class owns the switch and the
/// hardware it covers is listed beneath — same information, no lie.
struct DevicesPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        PaneScaffold(
            title: "Devices",
            subtitle: "Each kind of pointing device keeps its own direction. Changes apply the moment you scroll."
        ) {
            ForEach(PointingDeviceType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                deviceGroup(type)
            }
            newDeviceSection
            limitationNote
        }
    }

    private func deviceGroup(_ type: PointingDeviceType) -> some View {
        let rule = state.rule(for: type)
        let attached = state.devices(ofType: type)

        return VStack(alignment: .leading, spacing: 0) {
            SectionCaption(text: type.displayName)
            SettingsCard {
                SettingsRow(
                    title: "Direction",
                    subtitle: attached.isEmpty ? "Nothing of this kind is connected" : nil,
                    systemImage: symbol(for: type),
                    isDimmed: attached.isEmpty
                ) {
                    DirectionPicker(
                        isReversed: Binding(
                            get: { rule.reverseVertical },
                            set: { newValue in
                                var updated = rule
                                updated.reverseVertical = newValue
                                state.setRule(updated)
                            }
                        ),
                        isEnabled: state.settings.isEnabled && rule.isEnabled,
                        governs: type.displayName
                    )
                }

                RowDivider()

                SettingsRow(title: "Also reverse horizontal") {
                    Toggle("Also reverse horizontal", isOn: Binding(
                        get: { rule.reverseHorizontal },
                        set: { newValue in
                            var updated = rule
                            updated.reverseHorizontal = newValue
                            state.setRule(updated)
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!state.settings.isEnabled || !rule.isEnabled)
                }

                ForEach(attached) { device in
                    RowDivider()
                    SettingsRow(
                        title: device.name,
                        subtitle: device.subtitle,
                        systemImage: symbol(for: type)
                    ) {
                        Text("Covered")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var newDeviceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionCaption(text: "New devices")
            SettingsCard {
                SettingsRow(
                    title: "Default for anything new",
                    subtitle: "Applied when a kind of device is seen for the first time"
                ) {
                    DirectionPicker(
                        isReversed: Binding(
                            get: { state.settings.defaultForNewDevices.reverseVertical },
                            set: { newValue in
                                var updated = state.settings.defaultForNewDevices
                                updated.reverseVertical = newValue
                                state.setDefaultForNewDevices(updated)
                            }
                        ),
                        governs: "New device default"
                    )
                }
            }
        }
    }

    private var limitationNote: some View {
        Text("macOS does not tell an app which individual mouse produced a scroll, so a rule covers every device of its kind. Connected hardware is listed under the rule that governs it.")
            .font(.caption)
            // A paragraph the user is meant to read. `.tertiary` measures about
            // 2.2:1 in light mode, which is fine for a chevron and not for prose.
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func symbol(for type: PointingDeviceType) -> String {
        switch type {
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .mouse: "computermouse"
        case .tablet: "pencil.tip"
        case .unknown: "questionmark.circle"
        }
    }
}
