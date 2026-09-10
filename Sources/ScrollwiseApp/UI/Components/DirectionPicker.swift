import SwiftUI
import ScrollwiseCore

/// The Natural / Reversed segmented control from mockup 1b.
///
/// A picker rather than a switch because the two states are named opposites, not
/// on/off — "Reversed off" reads as a double negative. Both options carry real
/// labels, so VoiceOver announces the choice instead of "selected, button".
struct DirectionPicker: View {
    @Binding var isReversed: Bool
    var isEnabled: Bool = true
    /// What this picker governs — "Trackpad", "Mouse", "Tablet". Without it every
    /// picker in the Devices pane announces the same words and VoiceOver gives
    /// no way to tell which device is being changed.
    var governs: String?

    private var label: String {
        guard let governs else { return "Scroll direction" }
        return "\(governs) scroll direction"
    }

    var body: some View {
        // The Picker's own label is the accessibility label. Adding
        // `.accessibilityLabel` on top of it does not replace that label, it
        // appends — which is how this used to announce itself twice.
        Picker(label, selection: $isReversed) {
            Text("Natural").tag(false)
            Text("Reversed").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(!isEnabled)
        .accessibilityValue(isReversed ? "Reversed" : "Natural")
    }
}

/// A labelled row inside a `SettingsCard`.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var isDimmed: Bool = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(isDimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Metrics.rowVerticalPadding)
        // No `.opacity` here: the subtitle is already `.secondary`, and halving
        // that lands around 1.8:1 — below anything readable. `isDimmed` shifts
        // the title to the secondary style instead.

    }
}
