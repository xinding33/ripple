import Foundation

/// Open at Login is a LaunchAgent in ~/Library/LaunchAgents rather than SMAppService, so it can point at
/// Homebrew's version-independent opt/ path and keep working across `brew upgrade`.
enum LoginItem {
    private static let label = "com.xinding.Ripple"
    private static let agentURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist")

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: agentURL.path) }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try write() } else { try FileManager.default.removeItem(at: agentURL) }
    }

    /// Rewrites the agent so it points at this copy of the app, e.g. after it was moved.
    static func refresh() {
        if isEnabled { try? write() }
    }

    private static var stableExecutablePath: String {
        Bundle.main.bundlePath.replacingOccurrences(
            of: #"/Cellar/ripple/[^/]+/"#, with: "/opt/ripple/", options: .regularExpression
        ) + "/Contents/MacOS/Ripple"
    }

    private static func write() throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [stableExecutablePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agentURL)
    }
}
