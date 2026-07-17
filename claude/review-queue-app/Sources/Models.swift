// Models.swift — observable state. PRReview owns one PR's run lifecycle and its
// live-rendered transcript; AppModel owns discovery and the concurrency-capped
// run queue.
//
// Threading: @Published mutations happen on the main thread only. Async work
// hops back via MainActor.run; Process callbacks (background threads) hop back
// via DispatchQueue.main.async, which preserves stream order.

import Foundation
import SwiftUI

enum RunState {
    case queued, running, done, failed

    var symbol: String {
        switch self {
        case .queued:  return "circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .done:    return "checkmark.circle.fill"
        case .failed:  return "xmark.octagon.fill"
        }
    }
    var tint: Color {
        switch self {
        case .queued:  return Theme.ink3
        case .running: return Theme.accent
        case .done:    return Theme.good
        case .failed:  return Theme.crit
        }
    }
    var label: String {
        switch self {
        case .queued:  return "Queued"
        case .running: return "Running"
        case .done:    return "Done"
        case .failed:  return "Failed"
        }
    }
}

// How a review was started — shown as a small badge on running/completed rows so
// you can tell a hand-picked run from one auto-review kicked off on its own.
enum RunSource {
    case manual, auto

    var label: String { self == .auto ? "auto" : "manual" }
    var tint: Color { self == .auto ? Theme.sourceAuto : Theme.ink2 }
}

final class PRReview: ObservableObject, Identifiable {
    let id: String          // PR url — stable identity
    let repo: String
    let name: String
    let number: Int
    let url: String
    let title: String
    let reason: String

    @Published var selected: Bool = true
    @Published var state: RunState = .queued
    @Published var source: RunSource = .manual
    @Published var items: [RenderItem] = []
    @Published var exitCode: Int32? = nil

    private var parser = ReviewStreamParser()
    var process: Process?

    init(_ p: PRItem) {
        id = p.url; repo = p.repo; name = p.name; number = p.number
        url = p.url; title = p.title; reason = p.reason
    }

    /// Human-friendly eligibility reason (matches the spec's wording).
    var reasonLabel: String {
        switch reason {
        case "never_reviewed":                      return "never reviewed"
        case "new_commits_since_changes_requested": return "new commits since your changes-requested"
        case "prior_review_not_approved":           return "prior review not approved"
        default:                                    return reason
        }
    }

    // Must run on the main thread.
    func resetForRun() {
        items = []
        exitCode = nil
        parser = ReviewStreamParser()
        state = .queued
    }

    func ingest(_ data: Data) {
        let new = parser.consume(data)
        if !new.isEmpty {
            items.append(contentsOf: new)
            items = dedupedFinalSummary(items)
        }
    }

    func finish(_ code: Int32) {
        items.append(contentsOf: parser.flush())
        items = dedupedFinalSummary(items)
        exitCode = code
        let sawSuccess = items.contains {
            if case .finished(true, _) = $0 { return true } else { return false }
        }
        state = (code == 0 && sawSuccess) ? .done : .failed
    }
}

extension SkippedPR {
    /// Human-friendly skip reason for the dimmed sidebar rows.
    var reasonLabel: String {
        switch reason {
        case "clone_failed":                      return "checkout clone failed"
        case "ci_not_green":                      return "CI not green"
        case "approved":                          return "already approved"
        case "changes_requested_no_new_commits":  return "changes requested — no new commits"
        default:                                  return reason
        }
    }
}

// The verdict an auto-review actually posted to GitHub, queried via
// `review-queue --verdict` after the run (ground truth, not a transcript guess).
enum Verdict {
    case approved, changesRequested, commented, none, failed

    init(state: String?, runFailed: Bool) {
        if runFailed { self = .failed; return }
        switch (state ?? "").uppercased() {
        case "APPROVED":          self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        case "COMMENTED":         self = .commented
        default:                  self = .none   // DISMISSED / NONE / unknown
        }
    }

    var label: String {
        switch self {
        case .approved:         return "Approved"
        case .changesRequested: return "Changes requested"
        case .commented:        return "Commented"
        case .none:             return "No review posted"
        case .failed:           return "Run failed"
        }
    }
    var symbol: String {
        switch self {
        case .approved:         return "checkmark.circle.fill"
        case .changesRequested: return "exclamationmark.bubble.fill"
        case .commented:        return "text.bubble.fill"
        case .none:             return "questionmark.circle"
        case .failed:           return "xmark.octagon.fill"
        }
    }
    var tint: Color {
        switch self {
        case .approved:         return Theme.good
        case .changesRequested: return Theme.crit
        case .commented:        return Theme.commented
        case .none:             return Theme.ink3
        case .failed:           return Theme.crit
        }
    }
}

// One finished review — manual or auto — archived until the user dismisses it.
// Every completed run lands here (this is what makes results survive a window
// close). Held in memory only, not persisted across an app quit (by design).
// Re-reviews are flagged from the discovery reason so the row shows *why* the PR
// was reviewed again.
struct CompletedReview: Identifiable {
    let id: String          // url + finish time — stable, allows repeat entries per PR
    let repo: String
    let name: String
    let number: Int
    let url: String
    let title: String
    let reason: String
    let source: RunSource
    let verdict: Verdict
    let finishedAt: Date
    let items: [RenderItem]

    var isReReview: Bool {
        reason == "new_commits_since_changes_requested" || reason == "prior_review_not_approved"
    }
}

final class AppModel: ObservableObject {
    enum Phase { case idle, loading, ready, running, error }

    // `reviews` holds the *active* pipeline only: queued + running. A review
    // leaves this array the moment it finishes and is archived into `completed`.
    @Published var reviews: [PRReview] = []
    @Published var skipped: [SkippedPR] = []
    @Published var phase: Phase = .idle
    @Published var runPreamble: Bool = true
    @Published var maxConcurrent: Int = 1
    @Published var statusLine: String = "Idle."
    @Published var preambleLog: String = ""
    /// The row selected in the sidebar — a PRReview.url (live) or a
    /// CompletedReview.id (archived). Lives on the model so run-completion and
    /// refresh can keep it pointed at the right row across the archive handoff.
    @Published var selection: String? = nil

    // Auto-review: a periodic poll that discovers eligible PRs and reviews them
    // unattended, archiving each result alongside the manual ones.
    @Published var autoMode: Bool = false { didSet { if autoMode != oldValue { autoModeChanged() } } }
    @Published var autoIntervalMinutes: Int = 15 { didSet { if autoMode { scheduleTimer() } } }
    /// Every finished review, manual or auto, newest first, until dismissed.
    @Published var completed: [CompletedReview] = []
    /// When the next auto-review poll will fire (nil when auto-review is off).
    @Published var nextAutoCheck: Date? = nil
    /// Non-nil while auto-review is paused on a GitHub rate limit; the date it resumes.
    @Published var rateLimitedUntil: Date? = nil

    private var pending: [PRReview] = []
    private var active = 0
    /// Tallies for the current run batch's completion message (reviews are removed
    /// from `reviews` as they finish, so we can't count states after the fact).
    private var batchDone = 0
    private var batchFailed = 0
    /// True for the duration of an auto-initiated run batch (vs. a manual Run).
    private var autoRunActive = false
    /// Set when a discovery was kicked off by the poll timer; consumed in applyListResult.
    private var autoRunAfterDiscovery = false

    private var pollTimer: Timer?
    private var resumeTimer: Timer?
    private var activity: NSObjectProtocol?   // App Nap / termination assertion while auto is on

    /// Only queued rows are runnable; running/finished ones aren't re-run.
    var selectedCount: Int { reviews.filter { $0.selected && $0.state == .queued }.count }
    var queuedCount: Int { reviews.filter { $0.state == .queued }.count }
    var isBusy: Bool { phase == .loading || phase == .running }

    // MARK: Discovery

    func refresh() { startRefresh(autoRun: false) }

    private func startRefresh(autoRun: Bool) {
        guard !isBusy else { return }
        autoRunAfterDiscovery = autoRun
        phase = .loading
        statusLine = autoRun ? "Auto-review: discovering…" : "Discovering…"
        preambleLog = ""
        // The git-pull preamble pulls every repo and is too heavy to run on each
        // auto tick — only the manual Refresh button honours it.
        let doPreamble = runPreamble && !autoRun
        Task {
            if doPreamble {
                await MainActor.run { self.statusLine = "Running git-pull preamble (launch-claude.sh --no-open)…" }
                let pre = await ProcessRunner.collect(Paths.bash, [Paths.preamble.path, "--no-open"])
                await MainActor.run {
                    self.preambleLog = String(decoding: pre.out + pre.err, as: UTF8.self)
                }
            }
            await MainActor.run { self.statusLine = autoRun ? "Auto-review: review-queue --list-json…"
                                                            : "Running review-queue --list-json…" }
            let r = await ProcessRunner.collect(Paths.bash, [Paths.reviewQueueBin.path, "--list-json"])
            await MainActor.run { self.applyListResult(r) }
        }
    }

    private func applyListResult(_ r: (out: Data, err: Data, code: Int32)) {
        let runAuto = autoRunAfterDiscovery
        autoRunAfterDiscovery = false
        guard r.code == 0 else {
            let msg = String(decoding: r.err, as: UTF8.self)
            // A rate-limited discovery isn't a hard error — pause and resume later.
            if Self.looksRateLimited(msg) { enterRateLimited(); return }
            phase = .error
            statusLine = "list-json failed (exit \(r.code)). " + msg.prefix(200)
            return
        }
        do {
            let result = try JSONDecoder().decode(ListResult.self, from: r.out)
            // Never disturb an in-flight run; rebuild only the queued rows from
            // discovery. Completed reviews live in `completed` and are untouched,
            // so a PR reviewed earlier this session can legitimately reappear here
            // as a fresh re-review.
            let running = reviews.filter { $0.state == .running }
            let runningUrls = Set(running.map { $0.url })
            let prior = Dictionary(uniqueKeysWithValues:
                reviews.filter { $0.state == .queued }.map { ($0.url, $0.selected) })
            reviews = running + result.eligible
                .filter { !runningUrls.contains($0.url) }
                .map { item -> PRReview in
                    let pr = PRReview(item)
                    if let was = prior[item.url] { pr.selected = was }
                    return pr
                }
            skipped = result.skipped
            phase = .ready
            let elig = result.eligible.isEmpty ? "No eligible PRs" : "\(result.eligible.count) eligible"
            let skip = result.skipped.isEmpty ? "" : ", \(result.skipped.count) skipped"
            statusLine = elig + skip + "."
            if runAuto { autoRunEligible() }
        } catch {
            phase = .error
            statusLine = "Could not parse list-json: \(error)"
        }
    }

    // MARK: Run queue (serial by default, capped at maxConcurrent)

    func runSelected() {
        guard !isBusy else { return }
        let queue = reviews.filter { $0.selected && $0.state == .queued }
        guard !queue.isEmpty else { return }
        queue.forEach { $0.resetForRun() }
        pending = queue
        active = 0; batchDone = 0; batchFailed = 0
        phase = .running
        statusLine = "Running \(queue.count) review(s), \(maxConcurrent) at a time…"
        startMore()
    }

    private func startMore() {
        // Never run two PRs from the same repo at once: they share one local
        // checkout ($CODE_ROOT/<name>), and concurrent `--run`s would race on
        // its detached HEAD, cross-contaminating each other's full-file context.
        // Skip any pending PR whose checkout is already busy; it stays queued and
        // is picked up the moment that repo frees up. This can't stall: if
        // active == 0 no checkout is busy, so some pending PR is always runnable.
        while active < maxConcurrent {
            let busy = Set(reviews.filter { $0.state == .running }.map { $0.name })
            guard let idx = pending.firstIndex(where: { !busy.contains($0.name) }) else { break }
            start(pending.remove(at: idx))
        }
        if active == 0 && pending.isEmpty && phase == .running {
            phase = .ready
            let wasAuto = autoRunActive
            autoRunActive = false
            let failed = batchFailed
            let done = batchDone
            if wasAuto {
                statusLine = failed == 0
                    ? "Auto-review: \(done) posted. Next check in \(autoIntervalMinutes) min."
                    : "Auto-review: \(done) posted, \(failed) failed."
            } else {
                statusLine = failed == 0 ? "All reviews finished." : "Finished — \(failed) failed."
            }
        }
    }

    private func start(_ r: PRReview) {
        active += 1
        r.state = .running
        let auto = autoRunActive
        r.source = auto ? .auto : .manual
        r.process = ProcessRunner.stream(
            Paths.bash,
            [Paths.reviewQueueBin.path, "--run", r.url],
            onData: { data in DispatchQueue.main.async { r.ingest(data) } },
            onExit: { code in
                DispatchQueue.main.async { self.completeRun(r, code: code, auto: auto) }
            }
        )
        if r.process == nil {   // spawn failed
            completeRun(r, code: -1, auto: auto)
        }
    }

    /// A run just exited: tally it, archive it (which removes it from the active
    /// list once the posted verdict is known), and pull the next pending review.
    private func completeRun(_ r: PRReview, code: Int32, auto: Bool) {
        r.finish(code)
        if r.state == .failed { batchFailed += 1 } else { batchDone += 1 }
        archive(r, auto: auto)
        active -= 1
        startMore()
    }

    func openInDesktop(_ r: PRReview) {
        ProcessRunner.openInTerminal(repoDir: Paths.codeRoot.appendingPathComponent(r.name), url: r.url)
    }

    // MARK: Auto-review (periodic poll + unattended runs)

    private func autoModeChanged() {
        if autoMode {
            beginActivityAssertion()
            scheduleTimer()
            tickIfReady()            // don't wait a full interval for the first run
        } else {
            pollTimer?.invalidate(); pollTimer = nil
            nextAutoCheck = nil
            clearRateLimit()
            endActivityAssertion()
            if phase == .ready { statusLine = "Auto-review off." }
        }
    }

    private func scheduleTimer() {
        pollTimer?.invalidate()
        let interval = TimeInterval(max(1, autoIntervalMinutes) * 60)
        nextAutoCheck = Date().addingTimeInterval(interval)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.nextAutoCheck = Date().addingTimeInterval(interval)
            self.tickIfReady()
        }
    }

    /// A poll tick: discover + auto-run, unless we're busy or paused on a limit.
    private func tickIfReady() {
        guard autoMode, !isBusy else { return }
        if let until = rateLimitedUntil, until > Date() { return }   // still paused
        startRefresh(autoRun: true)
    }

    /// Run every eligible PR from the just-completed discovery, unattended.
    private func autoRunEligible() {
        let queue = reviews.filter { $0.state == .queued }
        guard !queue.isEmpty else {
            statusLine = "Auto-review: nothing eligible. Next check in \(autoIntervalMinutes) min."
            return
        }
        queue.forEach { $0.selected = true; $0.resetForRun() }
        pending = queue
        active = 0; batchDone = 0; batchFailed = 0
        autoRunActive = true
        phase = .running
        statusLine = "Auto-review: running \(queue.count), \(maxConcurrent) at a time…"
        startMore()
    }

    /// Archive a finished review — manual or auto. Query the posted verdict
    /// (ground truth from `--verdict`, not the transcript), then move the run out
    /// of the active list into `completed`, keeping the sidebar selection on it if
    /// it was the row being viewed.
    private func archive(_ r: PRReview, auto: Bool) {
        let runFailed = (r.state == .failed)
        let snapshot = r.items
        let repo = r.repo, name = r.name, number = r.number
        let url = r.url, title = r.title, reason = r.reason
        let source: RunSource = auto ? .auto : .manual
        Task {
            var state: String? = nil
            if !runFailed {
                let v = await ProcessRunner.collect(Paths.bash, [Paths.reviewQueueBin.path, "--verdict", url])
                if v.code == 0,
                   let dec = try? JSONDecoder().decode(ReviewVerdict.self, from: v.out) {
                    state = dec.state
                } else if Self.looksRateLimited(String(decoding: v.err, as: UTF8.self)) {
                    await MainActor.run { self.enterRateLimited() }
                }
            }
            let verdict = Verdict(state: state, runFailed: runFailed)
            let now = Date()
            let entry = CompletedReview(
                id: "\(url)#\(now.timeIntervalSince1970)",
                repo: repo, name: name, number: number, url: url, title: title,
                reason: reason, source: source, verdict: verdict, finishedAt: now, items: snapshot)
            await MainActor.run {
                if self.selection == url { self.selection = entry.id }
                self.reviews.removeAll { $0.id == url }
                self.completed.insert(entry, at: 0)   // newest first
            }
        }
    }

    func dismiss(_ entry: CompletedReview) {
        completed.removeAll { $0.id == entry.id }
        if selection == entry.id { selection = nil }
    }
    func dismissAll() {
        let ids = Set(completed.map(\.id))
        completed.removeAll()
        if let s = selection, ids.contains(s) { selection = nil }
    }

    // MARK: Rate-limit pause / resume

    /// Pause auto-review until GitHub's limits recover, then resume automatically.
    func enterRateLimited() {
        if phase != .running { phase = .ready }
        Task {
            let rr = await ProcessRunner.collect(Paths.bash, [Paths.reviewQueueBin.path, "--rate-reset"])
            let txt = String(decoding: rr.out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            // Fall back to a 2-minute backoff when the endpoint reports no exhausted
            // primary resource (e.g. a secondary rate limit, which it doesn't list).
            let until: Date = {
                if let epoch = Double(txt), epoch > Date().timeIntervalSince1970 {
                    return Date(timeIntervalSince1970: epoch)
                }
                return Date().addingTimeInterval(120)
            }()
            await MainActor.run {
                self.rateLimitedUntil = until
                self.statusLine = "GitHub rate limit reached — auto-review paused until \(Self.timeFmt.string(from: until))."
                self.scheduleResume(at: until)
            }
        }
    }

    func resumeFromRateLimit() {
        resumeTimer?.invalidate(); resumeTimer = nil
        rateLimitedUntil = nil
        statusLine = "Resumed."
        tickIfReady()
    }

    private func scheduleResume(at date: Date) {
        resumeTimer?.invalidate()
        let delay = max(1, date.timeIntervalSinceNow)
        resumeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.resumeFromRateLimit()
        }
    }

    private func clearRateLimit() {
        resumeTimer?.invalidate(); resumeTimer = nil
        rateLimitedUntil = nil
    }

    // MARK: Helpers

    /// Keep the agent app lively (no App Nap, no automatic/sudden termination) while
    /// auto-review is on, so the poll timer still fires on a locked Mac. We use the
    /// AllowingIdleSystemSleep variant deliberately — a *sleeping* Mac should stop.
    private func beginActivityAssertion() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Review Queue auto-review polling")
    }
    private func endActivityAssertion() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
    }

    static func looksRateLimited(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("rate limit") || l.contains("secondary rate") || l.contains("was submitted too quickly")
    }

    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
}
