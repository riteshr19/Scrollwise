import Foundation
import Testing
@testable import ScrollwiseCore

@Suite("Settings model and persistence")
struct SettingsTests {

    @Test("shipped defaults reverse the mouse but leave the trackpad alone")
    func defaultsAreSensible() {
        let s = SettingsDefaults.settings
        #expect(s.rule(for: .mouse).reverseVertical == true)
        #expect(s.rule(for: .trackpad).reverseVertical == false)
        // Horizontal stays off everywhere until explicitly asked for.
        #expect(s.activeProfile.deviceRules.allSatisfy { $0.reverseHorizontal == false })
        #expect(s.isEnabled == true)
    }

    @Test("replacing a rule does not mutate the original settings")
    func updatesAreImmutable() {
        let original = SettingsDefaults.settings
        let changed = original.replacingActiveRule(
            DeviceRule(device: .trackpad, reverseVertical: true)
        )
        #expect(original.rule(for: .trackpad).reverseVertical == false)
        #expect(changed.rule(for: .trackpad).reverseVertical == true)
    }

    @Test("settings survive a round trip through storage")
    func persistenceRoundTrip() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        var original = SettingsDefaults.settings
        original.isEnabled = false
        original.appRules = [AppRule(bundleIdentifier: "com.example.App", displayName: "Example")]
        original = original.replacingActiveRule(
            DeviceRule(device: .trackpad, reverseVertical: true, reverseHorizontal: true)
        )

        store.save(original)
        #expect(store.load() == original)
    }

    @Test("unreadable stored data falls back to defaults instead of throwing")
    func corruptionFallsBackSafely() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not json".utf8), forKey: SettingsStore.storageKey)
        // A settings problem must never stop scrolling from working.
        #expect(SettingsStore(defaults: defaults).load() == SettingsDefaults.settings)
    }

    @Test("an unset store returns the shipped defaults")
    func emptyStoreUsesDefaults() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SettingsStore(defaults: defaults).load() == SettingsDefaults.settings)
    }

    /// No UI anywhere sets `DeviceRule.isEnabled`, so a rule shipped disabled
    /// can never be switched back on and its Direction control is dead for good.
    @Test("every shipped device rule is enabled, so no control is unreachable")
    func shippedRulesAreReachable() {
        for rule in SettingsDefaults.deviceRules {
            #expect(rule.isEnabled, "\(rule.device) rule shipped disabled")
        }
    }

    @Test("a tablet ships governed but not reversed")
    func tabletDefault() {
        let tablet = SettingsDefaults.deviceRules.first { $0.device == .tablet }
        #expect(tablet != nil)
        #expect(tablet?.reverseVertical == false)
    }
}
