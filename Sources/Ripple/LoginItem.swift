import Foundation
import RippleCore

/// Open at Login is a LaunchAgent in ~/Library/LaunchAgents that opens this copy of the app.
enum LoginItem {
    private static let agent = LaunchAgent(label: bundleID)

    static var isEnabled: Bool { agent.exists }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try agent.write(executable: executablePath) } else { try agent.remove() }
    }

    /// Rewrites the agent so it points at this copy of the app, e.g. after it was moved.
    static func refresh() {
        if isEnabled { try? agent.write(executable: executablePath) }
    }

    /// Keeps Open at Login on for someone upgrading from a build that used the legacy label.
    static func migrateLegacyAgent() {
        do {
            try agent.replace(LaunchAgent(label: legacyBundleID), executable: executablePath)
        } catch {
            log.error("Couldn't move the login agent: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var executablePath: String { Bundle.main.bundlePath + "/Contents/MacOS/Ripple" }
}
