import AppKit
import Observation
import ScrollwiseCore
import ScrollwiseEngine

/// The single observable source of truth the whole UI reads.
///
/// Every control in the interface is bound to a value here, and every value here
/// is pushed straight into the engine. There is no path by which a switch can
/// look on while the engine is off — which is the point of §59 of the brief.
@MainActor
@Observable
final class AppState {

    // MARK: - Observable state

    private(set) var settings: ScrollSettings
    private(set) var accessibility: AccessibilityStatus = .denied
    private(set) var attachedDevices: [AttachedDevice] = []
    /// True only once the tap has actually attached — never on the strength of
    /// having asked for one. See `ScrollEngine.State`.
    private(set) var isEngineRunning = false
    /// Whether ⌥⌘R belongs to Scrollwise. Surfaces show the keys only when it does.
    private(set) var isShortcutRegistered = false
    /// Frontmost app, cached for the "Skip in this app" row.
    private(set) var frontmostApp: (bundleID: String, name: String)?
    private(set) var launchAtLoginAvailable = true
    private(set) var launchAtLoginNeedsApproval = false
    private(set) var launchAtLoginRefusal: String?

    // MARK: - Collaborators

    private let store: SettingsStore
    private let snapshot: SnapshotBox
    private let engine: ScrollEngine
    private let permissions = AccessibilityService()
    private let inventory = HIDDeviceInventory()
    private let shortcuts = GlobalShortcutService()
    private var frontmostMonitor: FrontmostAppMonitor?

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        let loaded = store.load()
        self.settings = loaded
        self.snapshot = SnapshotBox(EngineSnapshot(settings: loaded))
        self.engine = ScrollEngine(snapshot: snapshot)
    }

    // MARK: - Lifecycle

    func start() {
        engine.onStateChange = { [weak self] state in
            self?.engineStateChanged(state)
        }

        permissions.start { [weak self] status in
            guard let self else { return }
            self.accessibility = status
            self.engine.reconcile(with: status)
        }
        accessibility = permissions.status
        engine.reconcile(with: accessibility)

        let monitor = FrontmostAppMonitor { [weak self] bundleID in
            guard let self else { return }
            self.engine.apply(frontmostBundleID: bundleID)
            self.frontmostApp = Self.describeFrontmost(bundleID)
        }
        monitor.start()
        frontmostMonitor = monitor

        refreshLaunchAtLogin()
        // Trust the system over what we last wrote down: the user can revoke the
        // login item in System Settings without telling us.
        reconcileLaunchAtLogin()

        refreshDevices()
        inventory.onChange = { [weak self] in
            guard let self else { return }
            self.attachedDevices = self.inventory.devices
            Log.devices.info("Device set changed — list refreshed")
        }
        inventory.startObserving()

        shortcuts.register { [weak self] in
            self?.toggleEnabled()
        }
        isShortcutRegistered = shortcuts.isRegistered
    }

    /// Called from `applicationWillTerminate`. Leaves nothing running: the
    /// engine's stop waits for the tap thread to exit.
    func shutDown() {
        shortcuts.unregister()
        isShortcutRegistered = false
        engine.stop()
        permissions.stop()
        inventory.stopObserving()
        frontmostMonitor?.stop()
        frontmostMonitor = nil
        isEngineRunning = false
        Log.lifecycle.info("Application shut down cleanly")
    }

    /// The engine's own account of whether a tap is attached is what the UI
    /// shows, and what tells the permission model a grant is not working.
    private func engineStateChanged(_ state: ScrollEngine.State) {
        isEngineRunning = state == .running
        switch state {
        case .running: permissions.noteTapInstalled()
        case .failed: permissions.noteTapCreationFailed()
        case .stopped, .starting: break
        }
        accessibility = permissions.status
    }

    // MARK: - Mutations (all immutable updates, then one persist + one push)

    func setEnabled(_ enabled: Bool) {
        var updated = settings
        updated.isEnabled = enabled
        commit(updated)
    }

    func setRule(_ rule: DeviceRule) {
        commit(settings.replacingActiveRule(rule))
    }

    func setDefaultForNewDevices(_ rule: DeviceRule) {
        var updated = settings
        updated.defaultForNewDevices = rule
        commit(updated)
    }

    func setActiveProfile(_ id: UUID) {
        guard settings.profiles.contains(where: { $0.id == id }) else { return }
        var updated = settings
        updated.activeProfileID = id
        commit(updated)
    }

    func addProfile(named name: String) {
        // New profiles start from the current one, which is almost always what
        // the user means by "another set like this but for gaming".
        let copy = Profile(name: name, deviceRules: settings.activeProfile.deviceRules)
        var updated = settings
        updated.profiles.append(copy)
        updated.activeProfileID = copy.id
        commit(updated)
    }

    func removeProfile(_ id: UUID) {
        guard settings.profiles.count > 1 else { return }
        var updated = settings
        updated.profiles.removeAll { $0.id == id }
        if updated.activeProfileID == id {
            updated.activeProfileID = updated.profiles[0].id
        }
        commit(updated)
    }

    /// The global shortcut's action.
    func toggleEnabled() {
        setEnabled(!settings.isEnabled)
    }

    func upsertAppRule(_ rule: AppRule) {
        var updated = settings
        if let index = updated.appRules.firstIndex(where: { $0.bundleIdentifier == rule.bundleIdentifier }) {
            updated.appRules[index] = rule
        } else {
            updated.appRules.append(rule)
        }
        commit(updated)
    }

    func removeAppRule(bundleIdentifier: String) {
        var updated = settings
        updated.appRules.removeAll { $0.bundleIdentifier == bundleIdentifier }
        commit(updated)
    }

    /// Asks the system first and records only what it actually achieved, so the
    /// switch can never show a state the system disagrees with. A refusal is
    /// reported through `launchAtLoginRefusal`, which the General pane shows.
    func setLaunchAtLogin(_ enabled: Bool) {
        switch LaunchAtLoginService.setEnabled(enabled) {
        case .success(let achieved):
            var updated = settings
            updated.launchAtLogin = achieved
            commit(updated)
        case .failure:
            reconcileLaunchAtLogin()
        }
        refreshLaunchAtLogin()
    }

    func openLoginItemsSettings() {
        LaunchAtLoginService.openSystemSettings()
    }

    /// Re-reads what the system can change behind the app's back — hardware,
    /// and a login item approved or revoked in System Settings. Called when a
    /// surface appears; cheap, and never on a timer.
    func refreshSystemState() {
        refreshDevices()
        refreshLaunchAtLogin()
        reconcileLaunchAtLogin()
    }

    /// Mirrors what the system reports about the login item. Availability is
    /// only ever revoked by an actual refusal — see `LaunchAtLoginService`.
    private func refreshLaunchAtLogin() {
        launchAtLoginAvailable = LaunchAtLoginService.isAvailable
        launchAtLoginNeedsApproval = LaunchAtLoginService.needsApproval
        launchAtLoginRefusal = LaunchAtLoginService.refusalReason
    }

    private func reconcileLaunchAtLogin() {
        let actual = LaunchAtLoginService.isEnabled
        guard actual != settings.launchAtLogin else { return }
        var updated = settings
        updated.launchAtLogin = actual
        commit(updated)
    }

    /// The one place settings are written. The engine receives the complete new
    /// value in one swap, so it can never act on half of a change. Persistence
    /// failing is logged by the store and does not stop the engine or the UI —
    /// both show the value the engine is actually using.
    private func commit(_ updated: ScrollSettings) {
        guard updated != settings else { return }
        settings = updated
        store.save(updated)
        engine.apply(settings: updated)
    }

    // MARK: - Permissions & devices

    func requestAccessibility() {
        permissions.requestAccess()
    }

    func openAccessibilitySettings() {
        permissions.openSystemSettings()
    }

    func refreshDevices() {
        attachedDevices = inventory.refresh()
    }

    /// Resolves a bundle id to a display name, ignoring our own app so the
    /// "Skip in this app" row never offers to except Scrollwise itself.
    private static func describeFrontmost(_ bundleID: String?) -> (String, String)? {
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier else { return nil }
        let name = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .localizedName ?? bundleID
        return (bundleID, name)
    }

    /// The rule covering the frontmost app, if one exists.
    var frontmostAppRule: AppRule? {
        guard let frontmostApp else { return nil }
        return settings.appRules.first { $0.bundleIdentifier == frontmostApp.bundleID }
    }

    /// Toggles a passthrough rule for whatever is frontmost.
    func setSkipFrontmostApp(_ skip: Bool) {
        guard let frontmostApp else { return }
        if skip {
            upsertAppRule(AppRule(
                bundleIdentifier: frontmostApp.bundleID,
                displayName: frontmostApp.name,
                action: .passthrough
            ))
        } else {
            removeAppRule(bundleIdentifier: frontmostApp.bundleID)
        }
    }

    // MARK: - Derived, for the UI

    /// The honest headline. Reversal is only "on" when permission allows it,
    /// the engine is attached, and the master switch is on.
    var isActive: Bool {
        accessibility.allowsEngine && isEngineRunning && settings.isEnabled
    }

    /// Whether anything connected is actually being changed right now: some
    /// attached kind of device whose scrolling the rules flip, in the app that is
    /// frontmost. "Reversing" is claimed only then. `isActive` alone read
    /// "Reversing" above "Nothing is being reversed" whenever the one reversed
    /// class had no hardware attached. The decision is the engine's own
    /// `ScrollTransformer`, so the headline cannot disagree with the tap.
    var isReversingSomething: Bool {
        guard isActive else { return false }
        let frontmost = frontmostApp?.bundleID
        return PointingDeviceType.allCases.contains { type in
            type != .unknown && !devices(ofType: type).isEmpty
                && !ScrollTransformer.flip(device: type, frontmostBundleID: frontmost, settings: settings).isIdentity
        }
    }

    var activeDeviceCount: Int {
        settings.activeProfile.deviceRules.filter {
            $0.isEnabled && ($0.reverseVertical || $0.reverseHorizontal)
        }.count
    }

    /// Device classes that are switched on *and* have hardware attached — what
    /// is actually being reversed right now. `activeDeviceCount` counts rules,
    /// which is why it can claim "1 device" with nothing plugged in.
    var activeAttachedDeviceCount: Int {
        settings.activeProfile.deviceRules.filter {
            $0.isEnabled && ($0.reverseVertical || $0.reverseHorizontal)
                && !devices(ofType: $0.device).isEmpty
        }.count
    }

    var enabledAppRuleCount: Int {
        settings.appRules.filter(\.isEnabled).count
    }

    func rule(for device: PointingDeviceType) -> DeviceRule {
        settings.rule(for: device)
    }

    /// Attached hardware grouped under the class whose rule governs it.
    func devices(ofType type: PointingDeviceType) -> [AttachedDevice] {
        attachedDevices.filter { $0.type == type }
    }
}
