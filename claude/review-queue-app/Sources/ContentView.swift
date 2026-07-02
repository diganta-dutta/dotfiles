// ContentView.swift — the window UI. A controls header, an optional auto-review
// status strip, and a single flat sidebar that shows the whole review lifecycle
// (To review → Running → Completed → Skipped) beside a detail pane that renders
// whichever row is selected — a live-streaming transcript or an archived one.

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.rateLimitedUntil != nil {
                rateLimitBanner
            } else if model.autoMode {
                autoStrip
            }
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
                detail
                    .frame(minWidth: 460, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .tint(Theme.accent)   // primary buttons, checkboxes, switch, selection
        .onAppear {
            // REVIEW_QUEUE_NO_AUTO_REFRESH=1 boots the UI without running the
            // preamble/discovery (used for a side-effect-free smoke launch).
            if model.phase == .idle,
               ProcessInfo.processInfo.environment["REVIEW_QUEUE_NO_AUTO_REFRESH"] != "1" {
                model.refresh()
            }
        }
        // Keep a valid selection: when the lists change and nothing (or something
        // stale) is selected, fall to the first available row.
        .onChange(of: model.reviews.map(\.id) + model.completed.map(\.id)) { _, ids in
            if model.selection == nil || !ids.contains(model.selection!) {
                model.selection = ids.first
            }
        }
    }

    // MARK: Header controls

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { model.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)

                Toggle("git-pull preamble", isOn: $model.runPreamble)
                    .toggleStyle(.checkbox)
                    .disabled(model.isBusy)

                Picker("Concurrency", selection: $model.maxConcurrent) {
                    Text("Serial (1)").tag(1)
                    Text("2 at a time").tag(2)
                    Text("3 at a time").tag(3)
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(model.isBusy)

                Divider().frame(height: 16)

                Toggle("Auto-review", isOn: $model.autoMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Picker("every", selection: $model.autoIntervalMinutes) {
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(!model.autoMode)

                Spacer()

                Button {
                    model.runSelected()
                    model.selection = model.reviews.first(where: { $0.selected })?.id ?? model.selection
                } label: {
                    Label("Run \(model.selectedCount) selected", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.isBusy || model.selectedCount == 0)
            }
            HStack(spacing: 6) {
                if model.phase == .loading || model.phase == .running {
                    ProgressView().controlSize(.small)
                }
                Text(model.statusLine)
                    .font(.callout)
                    .foregroundStyle(model.phase == .error ? Theme.crit : Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.toolbarBG)
    }

    // MARK: Status strips

    private var autoStrip: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.good).frame(width: 7, height: 7)
            Text(autoStripText).font(.callout).foregroundStyle(Theme.accentText)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft)
    }

    private var autoStripText: String {
        let time = model.nextAutoCheck.map { AppModel.timeFmt.string(from: $0) } ?? "soon"
        if model.phase == .running { return "Auto-review on · reviewing now…" }
        let n = model.queuedCount
        if n == 0 { return "Auto-review on · next check \(time) · nothing eligible yet." }
        return "Auto-review on · next check \(time) · \(n) eligible will run automatically then."
    }

    private var rateLimitBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(Theme.warn)
            Text(model.rateLimitedUntil.map {
                "GitHub rate limit reached. Auto-review paused until \(AppModel.timeFmt.string(from: $0)), then resumes on its own."
            } ?? "")
                .font(.callout)
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("Resume now") { model.resumeFromRateLimit() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.warn.opacity(0.12))
    }

    // MARK: Unified lifecycle sidebar

    /// The per-row hint on queued PRs telling you when auto-review will pick them
    /// up (nil unless auto-review is on and not paused).
    private var queuedAutoHint: String? {
        guard model.autoMode, model.rateLimitedUntil == nil, let d = model.nextAutoCheck else { return nil }
        return "auto ~\(AppModel.timeFmt.string(from: d))"
    }

    private var toReview: [PRReview] { model.reviews.filter { $0.state == .queued } }
    private var running: [PRReview]  { model.reviews.filter { $0.state == .running } }

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section(header: sectionHeader("To review", toReview.count)) {
                if toReview.isEmpty && model.phase != .loading {
                    Text(model.phase == .error ? "Discovery failed — see status above."
                                               : "No eligible PRs.")
                        .font(.callout)
                        .foregroundStyle(Theme.ink2)
                }
                ForEach(toReview) { review in
                    PRRow(review: review, autoHint: queuedAutoHint).tag(review.id)
                }
            }

            if !running.isEmpty {
                Section(header: sectionHeader("Running", running.count)) {
                    ForEach(running) { review in
                        PRRow(review: review, autoHint: nil).tag(review.id)
                    }
                }
            }

            if !model.completed.isEmpty {
                Section(header: completedHeader) {
                    ForEach(model.completed) { entry in
                        CompletedRow(entry: entry).tag(entry.id)
                    }
                }
            }

            if !model.skipped.isEmpty {
                Section(header: sectionHeader("Skipped", model.skipped.count)) {
                    ForEach(model.skipped, id: \.url) { sk in
                        SkippedRow(skipped: sk)
                    }
                    .selectionDisabled(true)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarBG)
    }

    private func sectionHeader(_ title: String, _ count: Int) -> some View {
        Text("\(title) · \(count)")
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(Theme.ink3)
            .textCase(.uppercase)
    }

    private var completedHeader: some View {
        HStack {
            sectionHeader("Completed", model.completed.count)
            Spacer()
            Button("Dismiss all") { model.dismissAll() }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.caption)
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let id = model.selection, let review = model.reviews.first(where: { $0.id == id }) {
            LiveTranscriptView(review: review).environmentObject(model)
        } else if let id = model.selection, let entry = model.completed.first(where: { $0.id == id }) {
            CompletedTranscriptView(entry: entry).environmentObject(model)
        } else {
            ContentUnavailable(text: "Select a review to view its transcript.")
        }
    }
}

// MARK: - Shared row pieces

/// The small capsule marking how a run was started.
struct SourceBadge: View {
    let source: RunSource
    var body: some View {
        Text(source.label)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(source.tint.opacity(0.16)))
            .foregroundStyle(source.tint)
    }
}

/// A queued or running PR. @ObservedObject so the checkbox / spinner update live.
struct PRRow: View {
    @ObservedObject var review: PRReview
    let autoHint: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(review.name) #\(review.number)")
                        .font(.system(.body, design: .default).weight(.semibold))
                    if review.state == .running { SourceBadge(source: review.source) }
                }
                Text(review.title)
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(review.reasonLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.accentSoft))
                        .foregroundStyle(Theme.accentText)
                    if let autoHint, review.state == .queued {
                        Label(autoHint, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(Theme.accentText)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var leading: some View {
        if review.state == .running {
            ProgressView().controlSize(.small).padding(.top, 1)
        } else {
            Toggle("", isOn: $review.selected)
                .toggleStyle(.checkbox)
                .labelsHidden()
        }
    }
}

// One finished review: verdict, source, re-review tag, timestamp, dismiss.
struct CompletedRow: View {
    let entry: CompletedReview
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.verdict.symbol)
                .foregroundStyle(entry.verdict.tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(entry.name) #\(entry.number)")
                        .font(.system(.body).weight(.semibold))
                    SourceBadge(source: entry.source)
                    if entry.isReReview {
                        Label("re-review", systemImage: "arrow.clockwise")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.warn.opacity(0.15)))
                            .foregroundStyle(Theme.warn)
                    }
                }
                Text(entry.title).font(.caption).foregroundStyle(Theme.ink2).lineLimit(2)
                HStack(spacing: 8) {
                    Text(entry.verdict.label)
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(entry.verdict.tint)
                    Text(entry.finishedAt, style: .time)
                        .font(.caption2).foregroundStyle(Theme.ink2)
                }
            }
            Spacer()
            Button { model.dismiss(entry) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("Dismiss")
        }
        .padding(.vertical, 2)
    }
}

// A dimmed, non-selectable row for a PR discovery rejected.
struct SkippedRow: View {
    let skipped: SkippedPR

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(skipped.name) #\(skipped.number)")
                .font(.system(.body).weight(.medium))
                .foregroundStyle(Theme.ink2)
            Text(skipped.title)
                .font(.caption)
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
            Text(skipped.reasonLabel)
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Theme.ink2.opacity(0.15)))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.vertical, 2)
        .opacity(0.6)
    }
}

// MARK: - Detail panes

// The live transcript for one running/queued PR.
struct LiveTranscriptView: View {
    @ObservedObject var review: PRReview
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(review.name) #\(review.number)").font(.headline)
                    Text(review.title).font(.subheadline).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                Spacer()
                Label(review.state.label, systemImage: review.state.symbol)
                    .foregroundStyle(review.state.tint)
                Button {
                    model.openInDesktop(review)
                } label: {
                    Label("Open in Desktop", systemImage: "macwindow")
                }
                .help("Open Terminal in this repo and run claude interactively (no -p)")
            }
            .padding(12)
            Divider()
            TranscriptScroll(
                items: review.items,
                emptyText: review.state == .running ? "Waiting for first event…" : "No output yet. Press Run.",
                autoscroll: true)
        }
    }
}

// The stored transcript for one completed review, shown inline in the detail pane.
struct CompletedTranscriptView: View {
    let entry: CompletedReview
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(entry.name) #\(entry.number)").font(.headline)
                        SourceBadge(source: entry.source)
                    }
                    Text(entry.title).font(.subheadline).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                Spacer()
                Label(entry.verdict.label, systemImage: entry.verdict.symbol)
                    .foregroundStyle(entry.verdict.tint)
                if let url = URL(string: entry.url) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open on GitHub", systemImage: "arrow.up.right.square")
                    }
                }
                Button { model.dismiss(entry) } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
            }
            .padding(12)
            Divider()
            TranscriptScroll(items: entry.items, emptyText: "No transcript captured.", autoscroll: false)
        }
    }
}

// The scrolling transcript body, shared by live and archived panes.
struct TranscriptScroll: View {
    let items: [RenderItem]
    let emptyText: String
    let autoscroll: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if items.isEmpty {
                        Text(emptyText).foregroundStyle(Theme.ink2).padding(.top, 8)
                    }
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        ItemView(item: item).id(idx)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .onChange(of: items.count) { _, count in
                if autoscroll, count > 0 { withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) } }
            }
        }
    }
}

// Renders a single stream event.
struct ItemView: View {
    let item: RenderItem

    var body: some View {
        switch item {
        case .assistantText(let text):
            MarkdownView(text)

        case .toolCall(let name, _, let command):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(Theme.warn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(.callout, design: .monospaced)).bold()
                    if let command, !command.isEmpty {
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.warn.opacity(0.08)))

        case .toolResult(_, let isError):
            HStack(spacing: 6) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "arrow.turn.down.right")
                    .foregroundStyle(isError ? Theme.crit : Theme.ink3)
                Text(isError ? "tool error" : "tool result")
                    .font(.caption)
                    .foregroundStyle(isError ? Theme.crit : Theme.ink3)
            }

        case .finished(let success, let summary):
            VStack(alignment: .leading, spacing: 4) {
                Label(success ? "Review complete" : "Review failed",
                      systemImage: success ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(success ? Theme.good : Theme.crit)
                if !summary.isEmpty {
                    MarkdownView(summary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill((success ? Theme.good : Theme.crit).opacity(0.08)))
        }
    }
}

// Tiny placeholder (avoids depending on macOS 14 ContentUnavailableView).
struct ContentUnavailable: View {
    let text: String
    var body: some View {
        VStack { Spacer(); Text(text).foregroundStyle(Theme.ink2); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
