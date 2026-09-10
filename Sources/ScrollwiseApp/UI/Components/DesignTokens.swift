import SwiftUI

/// Shared metrics and colours.
///
/// ## Why there are almost no colours here
/// The mockups specify `#0071e3` — Apple's *marketing* blue from apple.com, not
/// the system accent colour. A native app must use `Color.accentColor`, which
/// follows whatever the user chose in Appearance settings and switches to grey
/// under "Graphite". Hard-coding a blue is one of the clearest tells that an
/// interface was drawn rather than built.
///
/// Likewise every text colour is semantic (`.primary`, `.secondary`), so it
/// tracks light/dark, Increase Contrast, and vibrancy over glass automatically.
/// The mockups' `rgba(0,0,0,.42)` captions would fail contrast in both themes.
enum Metrics {
    /// Matches the popover width in mockup 1d.
    static let popoverWidth: CGFloat = 340
    static let sidebarMinWidth: CGFloat = 196
    static let sidebarIdealWidth: CGFloat = 214
    static let detailMinWidth: CGFloat = 460
    static let windowMinHeight: CGFloat = 520

    static let cardCornerRadius: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 9
    static let sectionSpacing: CGFloat = 18
}

/// The tinted app-icon squares used in the sidebar and headers.
struct SymbolTile: View {
    let systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            // Decorative: the adjacent label already names the row.
            .accessibilityHidden(true)
    }
}

/// A grouped settings card. Uses the system's grouped-content background rather
/// than a hand-mixed translucent white, so it sits correctly on whatever
/// material the window provides and responds to Reduce Transparency for free.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
    }
}

/// Section caption above a card — the element the HTML mockups rendered wrong.
struct SectionCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
            // Lets VoiceOver treat the following card as a named group.
            .accessibilityAddTraits(.isHeader)
    }
}

/// Hairline between rows inside a card.
struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}
