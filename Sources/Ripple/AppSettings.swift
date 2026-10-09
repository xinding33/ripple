import Combine
import Foundation
import RippleCore

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let autoWake = "autoWake"
        static let keepAwake = "keepAwake"
        static let keepAwakeOnlyOnAC = "keepAwakeOnlyOnAC"
        static let shortcut = "wakeAllShortcut"
        static let installID = "installID"
        static let pairingCode = "pairingCode"
    }

    private let defaults = UserDefaults.standard

    /// Tell other Macs to wake when this Mac's display wakes.
    @Published var autoWake: Bool { didSet { defaults.set(autoWake, forKey: Keys.autoWake) } }
    /// Prevent idle system sleep so this Mac stays reachable (the display can still sleep).
    @Published var keepAwake: Bool { didSet { defaults.set(keepAwake, forKey: Keys.keepAwake) } }
    @Published var keepAwakeOnlyOnAC: Bool { didSet { defaults.set(keepAwakeOnlyOnAC, forKey: Keys.keepAwakeOnlyOnAC) } }
    @Published var shortcut: Shortcut? {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: Keys.shortcut) }
    }
    /// Stored in preferences, not the Keychain: builds from source are ad-hoc signed, so the Keychain would
    /// prompt again after every rebuild, and the code only authorizes waking displays.
    @Published var pairingCode: String { didSet { defaults.set(pairingCode, forKey: Keys.pairingCode) } }

    /// Identifies this install so a Mac ignores its own broadcasts.
    let installID: UUID

    private init() {
        defaults.register(defaults: [Keys.autoWake: true, Keys.keepAwake: true, Keys.keepAwakeOnlyOnAC: true])
        autoWake = defaults.bool(forKey: Keys.autoWake)
        keepAwake = defaults.bool(forKey: Keys.keepAwake)
        keepAwakeOnlyOnAC = defaults.bool(forKey: Keys.keepAwakeOnlyOnAC)

        if let data = defaults.data(forKey: Keys.shortcut) {
            shortcut = (try? JSONDecoder().decode(Shortcut?.self, from: data)) ?? nil
        } else {
            shortcut = .defaultWakeAll
        }

        // A `-pairingCode CODE` launch argument overrides the stored code without saving it (for testing).
        pairingCode = defaults.string(forKey: Keys.pairingCode) ?? ""

        if let stored = defaults.string(forKey: Keys.installID), let id = UUID(uuidString: stored) {
            installID = id
        } else {
            installID = UUID()
            defaults.set(installID.uuidString, forKey: Keys.installID)
        }
    }
}
