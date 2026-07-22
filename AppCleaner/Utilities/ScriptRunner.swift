import Foundation

/// Central place for AppleScript and privileged shell execution.
///
/// AppleScript runs through the `osascript` subprocess instead of in-process
/// NSAppleScript: the hardened runtime blocks in-process Apple Events sends
/// without the `com.apple.security.automation.apple-events` entitlement, while
/// TCC attributes a subprocess's requests to this app, so a single
/// "control Finder" permission covers everything.
enum ScriptRunner {
    struct RunResult {
        let output: String
        let exitCode: Int32
    }

    @discardableResult
    static func run(_ source: String) -> RunResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return RunResult(output: "", exitCode: -1)
        }
        proc.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return RunResult(output: text, exitCode: proc.terminationStatus)
    }

    /// Move a file to the Trash with Finder. Fallback for when
    /// NSWorkspace.recycle fails (TCC-protected locations like /Applications).
    static func finderDelete(path: String) -> Bool {
        let escaped = escapeForAppleScript(path)
        let result = run("tell application \"Finder\" to delete (POSIX file \"\(escaped)\" as alias)")
        return result.exitCode == 0 && !FileManager.default.fileExists(atPath: path)
    }

    static func emptyTrash() -> Bool {
        run("tell application \"Finder\" to empty trash").exitCode == 0
    }

    /// Runs a shell command as root after the standard macOS administrator
    /// password prompt. Returns false if the user cancels or the script fails.
    static func runPrivileged(_ shellCommand: String) -> Bool {
        let literal = escapeForAppleScript(shellCommand)
        return run("do shell script \"\(literal)\" with administrator privileges").exitCode == 0
    }

    /// Stop a launchd job in the current user's GUI domain. Errors (job not
    /// loaded) are ignored.
    static func bootoutUserJob(label: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
    }

    /// Single-quotes a path for safe use in a POSIX shell command.
    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
