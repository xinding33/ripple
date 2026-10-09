import Foundation

/// Moves state left by builds before the move from com.xinding.Ripple to a Developer ID bundle ID.
public enum LegacyMigration {
    /// Copies preferences from the legacy domain, keeping any already in the new one, then removes
    /// the legacy domain so this runs once.
    public static func migrateDefaults(from legacy: String, to domain: String, in defaults: PreferenceDomains = UserDefaults.standard) {
        guard let old = defaults.persistentDomain(forName: legacy), !old.isEmpty else { return }
        let current = defaults.persistentDomain(forName: domain) ?? [:]
        defaults.setPersistentDomain(old.merging(current) { _, new in new }, forName: domain)
        defaults.removePersistentDomain(forName: legacy)
    }
}

/// The parts of UserDefaults that migration uses, so tests can avoid the real preferences.
public protocol PreferenceDomains {
    func persistentDomain(forName domainName: String) -> [String: Any]?
    func setPersistentDomain(_ domain: [String: Any], forName domainName: String)
    func removePersistentDomain(forName domainName: String)
}

extension UserDefaults: PreferenceDomains {}

/// A per-user LaunchAgent that opens an app at login.
public struct LaunchAgent {
    public let label: String
    public let url: URL

    public init(label: String, directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents", isDirectory: true)) {
        self.label = label
        url = directory.appendingPathComponent("\(label).plist")
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func write(executable: String) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    }

    public func remove() throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Replaces an agent written by an earlier build under another label, keeping Open at Login on.
    public func replace(_ legacy: LaunchAgent, executable: String) throws {
        guard legacy.exists else { return }
        try write(executable: executable)
        try legacy.remove()
    }
}
