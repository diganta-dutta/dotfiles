// Backend.swift — paths, the JSON shape from `review-queue --list-json`, and the
// Process shell-out layer. No UI imports (Foundation only) so this file can also
// be compiled into the headless smoke test (see tests/Smoke.swift).
//
// Conventions borrowed from Claude Launcher (claude/launch):
//   - GUI-launched apps get a minimal PATH; we pin the tools we need.
//   - We never reimplement the git-pull-and-refresh preamble — we shell out to
//     launch-claude.sh --no-open, the exact step Claude Launcher runs.

import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Local checkout root that the backend script scans (overridable, matches
    /// review-queue's own CODE_ROOT default).
    static var codeRoot: URL {
        if let c = env["CODE_ROOT"], !c.isEmpty { return URL(fileURLWithPath: c) }
        return home.appendingPathComponent("code")
    }

    /// The Phase-2 workhorse, now living alongside the app in the dotfiles repo.
    /// Overridable via REVIEW_QUEUE_BIN.
    static var reviewQueueBin: URL {
        if let b = env["REVIEW_QUEUE_BIN"], !b.isEmpty { return URL(fileURLWithPath: b) }
        return home.appendingPathComponent("code/dotfiles/claude/review-queue-app/review-queue")
    }

    /// Claude Launcher's shared preamble. Overridable via LAUNCH_CLAUDE_BIN.
    static var preamble: URL {
        if let b = env["LAUNCH_CLAUDE_BIN"], !b.isEmpty { return URL(fileURLWithPath: b) }
        return home.appendingPathComponent("code/dotfiles/claude/launch/launch-claude.sh")
    }

    static let bash = URL(fileURLWithPath: "/bin/bash")
    static let osascript = URL(fileURLWithPath: "/usr/bin/osascript")

    /// Minimal PATH plus ~/.local/bin (where `claude` lives) and Homebrew (gh, jq).
    static let pinnedPATH =
        "\(home.path)/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

/// One eligible PR as emitted by `review-queue --list-json`.
struct PRItem: Decodable, Equatable {
    let repo: String
    let name: String
    let number: Int
    let url: String
    let title: String
    let reason: String
}

/// One PR that discovery rejected, with the machine reason it was skipped:
/// no_local_checkout | ci_not_green | approved | changes_requested_no_new_commits.
struct SkippedPR: Decodable, Equatable {
    let repo: String
    let name: String
    let number: Int
    let url: String
    let title: String
    let reason: String
}

/// The full `review-queue --list-json` document.
struct ListResult: Decodable {
    let eligible: [PRItem]
    let skipped: [SkippedPR]
}

enum ProcessRunner {
    private static func pinnedEnvironment() -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = Paths.pinnedPATH
        return e
    }

    /// Run to completion, collecting stdout/stderr fully. Used for the preamble
    /// and for `--list-json` (neither streams).
    static func collect(_ exe: URL, _ args: [String]) async -> (out: Data, err: Data, code: Int32) {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            p.environment = pinnedEnvironment()

            let op = Pipe(), ep = Pipe()
            p.standardOutput = op
            p.standardError = ep

            let q = DispatchQueue(label: "rq.collect")
            var outD = Data(), errD = Data()
            op.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; if !d.isEmpty { q.async { outD.append(d) } }
            }
            ep.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; if !d.isEmpty { q.async { errD.append(d) } }
            }
            p.terminationHandler = { proc in
                op.fileHandleForReading.readabilityHandler = nil
                ep.fileHandleForReading.readabilityHandler = nil
                let ro = try? op.fileHandleForReading.readToEnd()
                let re = try? ep.fileHandleForReading.readToEnd()
                q.async {
                    if let ro { outD.append(ro) }
                    if let re { errD.append(re) }
                    cont.resume(returning: (outD, errD, proc.terminationStatus))
                }
            }
            do { try p.run() }
            catch { cont.resume(returning: (Data(), Data("spawn failed: \(error)".utf8), -1)) }
        }
    }

    /// Spawn a long-running process, delivering stdout chunks live via `onData`
    /// (called on a background thread) and the exit code via `onExit`. stderr
    /// (git/diagnostic noise) is discarded. Returns the Process so the caller
    /// can terminate it.
    @discardableResult
    static func stream(_ exe: URL,
                       _ args: [String],
                       onData: @escaping (Data) -> Void,
                       onExit: @escaping (Int32) -> Void) -> Process? {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.environment = pinnedEnvironment()

        let op = Pipe()
        p.standardOutput = op
        p.standardError = FileHandle.nullDevice
        op.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData; if !d.isEmpty { onData(d) }
        }
        p.terminationHandler = { proc in
            op.fileHandleForReading.readabilityHandler = nil
            if let rest = try? op.fileHandleForReading.readToEnd(), !rest.isEmpty { onData(rest) }
            onExit(proc.terminationStatus)
        }
        do { try p.run() }
        catch { onExit(-1); return nil }
        return p
    }

    /// Take a review interactive: open Terminal in the repo dir and run claude
    /// WITHOUT -p, pre-seeded with the /review-pr slash command for this PR.
    static func openInTerminal(repoDir: URL, url: String) {
        let cmd = "cd \(shellQuote(repoDir.path)) && claude '/review-pr \(url)'"
        let escaped = cmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        let p = Process()
        p.executableURL = Paths.osascript
        p.arguments = ["-e", script]
        try? p.run()
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
