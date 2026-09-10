import SwiftUI
import ScrollwiseCore

/// Shown whenever the app cannot actually do what its controls imply.
///
/// This is the counterpart to the rule that the UI must never claim success it
/// has not achieved: when permission is missing or the tap is detached, the
/// banner says so and the affected controls are disabled rather than lying.
struct StatusBanner: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 15))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(13)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: Metrics.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                .strokeBorder(.orange.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(message)")
    }
}
