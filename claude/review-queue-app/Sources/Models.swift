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
        case .queued:  return .secondary
        case .running: return .blue
        case .done:    return .green
        case .failed:  return .red
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
        case "no_local_checkout":                 return "no local checkout"
        case "ci_not_green":                      return "CI not green"
        case "approved":                          return "already approved"
        case "changes_requested_no_new_commits":  return "changes requested — no new commits"
        default:                                  return reason
        }
    }
}

final class AppModel: ObservableObject {
    enum Phase { case idle, loading, ready, running, error }

    @Published var reviews: [PRReview] = []
    @Published var skipped: [SkippedPR] = []
    @Published var phase: Phase = .idle
    @Published var runPreamble: Bool = true
    @Published var maxConcurrent: Int = 1
    @Published var statusLine: String = "Idle."
    @Published var preambleLog: String = ""

    private var pending: [PRReview] = []
    private var active = 0

    var selectedCount: Int { reviews.filter { $0.selected }.count }
    var isBusy: Bool { phase == .loading || phase == .running }

    // MARK: Discovery

    func refresh() {
        guard !isBusy else { return }
        phase = .loading
        statusLine = "Discovering…"
        preambleLog = ""
        Task {
            if runPreamble {
                await MainActor.run { self.statusLine = "Running git-pull preamble (launch-claude.sh --no-open)…" }
                let pre = await ProcessRunner.collect(Paths.bash, [Paths.preamble.path, "--no-open"])
                await MainActor.run {
                    self.preambleLog = String(decoding: pre.out + pre.err, as: UTF8.self)
                }
            }
            await MainActor.run { self.statusLine = "Running review-queue --list-json…" }
            let r = await ProcessRunner.collect(Paths.bash, [Paths.reviewQueueBin.path, "--list-json"])
            await MainActor.run { self.applyListResult(r) }
        }
    }

    private func applyListResult(_ r: (out: Data, err: Data, code: Int32)) {
        guard r.code == 0 else {
            phase = .error
            let msg = String(decoding: r.err, as: UTF8.self)
            statusLine = "list-json failed (exit \(r.code)). " + msg.prefix(200)
            return
        }
        do {
            let result = try JSONDecoder().decode(ListResult.self, from: r.out)
            // Preserve prior selection for PRs still present across a refresh.
            let prior = Dictionary(uniqueKeysWithValues: reviews.map { ($0.id, $0.selected) })
            reviews = result.eligible.map { item in
                let pr = PRReview(item)
                if let was = prior[item.url] { pr.selected = was }
                return pr
            }
            skipped = result.skipped
            phase = .ready
            let elig = result.eligible.isEmpty ? "No eligible PRs" : "\(result.eligible.count) eligible"
            let skip = result.skipped.isEmpty ? "" : ", \(result.skipped.count) skipped"
            statusLine = elig + skip + "."
        } catch {
            phase = .error
            statusLine = "Could not parse list-json: \(error)"
        }
    }

    // MARK: Run queue (serial by default, capped at maxConcurrent)

    func runSelected() {
        guard !isBusy else { return }
        let queue = reviews.filter { $0.selected }
        guard !queue.isEmpty else { return }
        queue.forEach { $0.resetForRun() }
        pending = queue
        active = 0
        phase = .running
        statusLine = "Running \(queue.count) review(s), \(maxConcurrent) at a time…"
        startMore()
    }

    private func startMore() {
        while active < maxConcurrent, !pending.isEmpty {
            start(pending.removeFirst())
        }
        if active == 0 && pending.isEmpty && phase == .running {
            phase = .ready
            let failed = reviews.filter { $0.state == .failed }.count
            statusLine = failed == 0
                ? "All reviews finished."
                : "Finished — \(failed) failed."
        }
    }

    private func start(_ r: PRReview) {
        active += 1
        r.state = .running
        r.process = ProcessRunner.stream(
            Paths.bash,
            [Paths.reviewQueueBin.path, "--run", r.url],
            onData: { data in DispatchQueue.main.async { r.ingest(data) } },
            onExit: { code in
                DispatchQueue.main.async {
                    r.finish(code)
                    self.active -= 1
                    self.startMore()
                }
            }
        )
        if r.process == nil {   // spawn failed
            r.finish(-1)
            active -= 1
        }
    }

    func openInDesktop(_ r: PRReview) {
        ProcessRunner.openInTerminal(repoDir: Paths.codeRoot.appendingPathComponent(r.name), url: r.url)
    }
}
