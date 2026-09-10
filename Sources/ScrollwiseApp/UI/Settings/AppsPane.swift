import AppKit
import SwiftUI
import ScrollwiseCore

/// Per-app overrides. An app rule beats the device rule while that app is frontmost.
struct AppsPane: View {
    @Environment(AppState.self) private var state
    @State private var isImporting = false

    var body: some View {
        PaneScaffold(
            title: "Apps",
            subtitle: "Give an app its own behaviour. The rule applies whenever that app is frontmost."
        ) {
            if state.settings.appRules.isEmpty {
                emptyState
            } else {
                SettingsCard {
                    ForEach(Array(state.settings.appRules.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 { RowDivider() }
                        ruleRow(rule)
                    }
                }
            }
            addButton
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.application],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("No app rules yet").font(.body.weight(.medium))
            Text("Add an app to leave its scrolling alone, or to force a direction there.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardCornerRadius))
    }

    private func ruleRow(_ rule: AppRule) -> some View {
        SettingsRow(
            title: rule.displayName,
            subtitle: rule.bundleIdentifier,
            systemImage: "app"
        ) {
            HStack(spacing: 10) {
                Picker("Behaviour", selection: Binding(
                    get: { rule.action },
                    set: { newAction in
                        var updated = rule
                        updated.action = newAction
                        state.upsertAppRule(updated)
                    }
                )) {
                    ForEach(AppRuleAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Button {
                    state.removeAppRule(bundleIdentifier: rule.bundleIdentifier)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this rule")
                .accessibilityLabel("Remove rule for \(rule.displayName)")
            }
        }
    }

    private var addButton: some View {
        HStack(spacing: 10) {
            Button("Add App…") { isImporting = true }

            if let frontmost = state.frontmostApp, state.frontmostAppRule == nil {
                Button("Add \(frontmost.name)") {
                    state.upsertAppRule(AppRule(
                        bundleIdentifier: frontmost.bundleID,
                        displayName: frontmost.name
                    ))
                }
            }
        }
        .controlSize(.regular)
    }

    /// Reads the chosen bundle's real identifier and name — never a guess from
    /// the file name, which would silently produce a rule that never matches.
    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else {
            Log.settings.error("Selected item is not an application bundle")
            return
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        state.upsertAppRule(AppRule(bundleIdentifier: identifier, displayName: name))
    }
}
