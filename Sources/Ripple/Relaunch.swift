import Foundation

/// Restarts into the copy now at the app's path, e.g. after an update replaced it.
///
/// Not with `execv`: macOS 27 doesn't show the menu bar item of a process that has exec'd itself,
/// so the restarted app would run with no icon.
enum Relaunch {
    /// Starts the new copy and exits this one, without running the app's quit handling, as `execv`
    /// didn't either. Returns only if it couldn't, with the reason.
    static func now(agentLabel: String) -> String {
        if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == agentLabel {
            // Started by the login item. launchd stops this copy and starts the new one as the
            // same job, so the new copy still counts as started at login.
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            kickstart.arguments = ["kickstart", "-k", "gui/\(getuid())/\(agentLabel)"]
            do {
                try kickstart.run()
            } catch {
                return error.localizedDescription
            }
            kickstart.waitUntilExit()
            if kickstart.terminationStatus == 0 { exit(0) }
            // Keep running as the job rather than open a copy launchd wouldn't look after.
            return "launchctl kickstart failed with status \(kickstart.terminationStatus)"
        }
        // Something has to outlive this process and open the new copy, with the same arguments,
        // once it's gone.
        let script = #"""
            pid=$0 app=$1; shift
            while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
            if [ $# -gt 0 ]; then exec /usr/bin/open -n -g "$app" --args "$@"; fi
            exec /usr/bin/open -n -g "$app"
            """#
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", script, String(getpid()), Bundle.main.bundlePath] + CommandLine.arguments.dropFirst()
        reopen.standardInput = FileHandle.nullDevice
        reopen.standardOutput = FileHandle.nullDevice
        reopen.standardError = FileHandle.nullDevice
        do {
            try reopen.run()
        } catch {
            return error.localizedDescription
        }
        exit(0)
    }
}
