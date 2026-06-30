// ContentView.swift — the window UI: a controls header, a checklist sidebar
// (the deselect-a-subset capability that justifies this being an app), and a
// per-PR live-streaming transcript detail pane.

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: String?
    @State private var tab: Tab = .queue

    enum Tab: Hashable { case queue, inbox }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.rateLimitedUntil != nil { rateLimitBanner }
            Divider()
            tabPicker
            Divider()
            switch tab {
            case .queue:
                NavigationSplitView {
                    sidebar.navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
                } detail: {
                    detail
                }
            case .inbox:
                InboxView()
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            // REVIEW_QUEUE_NO_AUTO_REFRESH=1 boots the UI without running the
            // preamble/discovery (used for a side-effect-free smoke launch).
            if model.phase == .idle,
               ProcessInfo.processInfo.environment["REVIEW_QUEUE_NO_AUTO_REFRESH"] != "1" {
                model.refresh()
            }
        }
        .onChange(of: model.reviews.map(\.id)) { _, ids in
            if selection == nil || !(ids.contains(selection!)) { selection = ids.first }
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            Text("Live queue (\(model.reviews.count))").tag(Tab.queue)
            Text("Auto-review inbox (\(model.inbox.count))").tag(Tab.inbox)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var rateLimitBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text(model.rateLimitedUntil.map {
                "GitHub rate limit reached. Auto-review paused until \(AppModel.timeFmt.string(from: $0)), then resumes on its own."
            } ?? "")
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            Button("Resume now") { model.resumeFromRateLimit() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: Header controls

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { model.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
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
                    selection = model.reviews.first(where: { $0.selected })?.id ?? selection
                } label: {
                    Label("Run \(model.selectedCount) selected", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.isBusy || model.selectedCount == 0)
            }
            HStack(spacing: 6) {
                if model.phase == .loading || model.phase == .running {
                    ProgressView().controlSize(.small)
                }
                Text(model.statusLine)
                    .font(.callout)
                    .foregroundStyle(model.phase == .error ? .red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(12)
    }

    // MARK: Sidebar checklist

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Eligible (\(model.reviews.count))") {
                if model.reviews.isEmpty && model.phase != .loading {
                    Text(model.phase == .error ? "Discovery failed — see status above."
                                               : "No eligible PRs.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.reviews) { review in
                    PRRow(review: review).tag(review.id)
                }
            }
            if !model.skipped.isEmpty {
                Section("Skipped (\(model.skipped.count))") {
                    ForEach(model.skipped, id: \.url) { sk in
                        SkippedRow(skipped: sk)
                    }
                    .selectionDisabled(true)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let id = selection, let review = model.reviews.first(where: { $0.id == id }) {
            TranscriptView(review: review)
                .environmentObject(model)
        } else {
            ContentUnavailable(text: "Select a PR to view its review.")
        }
    }
}

// One checklist row. @ObservedObject so the checkbox and state icon update live.
struct PRRow: View {
    @ObservedObject var review: PRReview

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $review.selected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text("\(review.name) #\(review.number)")
                    .font(.system(.body, design: .default).weight(.semibold))
                Text(review.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(review.reasonLabel)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            stateIcon
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var stateIcon: some View {
        if review.state == .running {
            ProgressView().controlSize(.small)
        } else if review.state != .queued {
            Image(systemName: review.state.symbol)
                .foregroundStyle(review.state.tint)
                .help(review.state.label)
        }
    }
}

// A dimmed, non-selectable row for a PR discovery rejected.
struct SkippedRow: View {
    let skipped: SkippedPR

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(skipped.name) #\(skipped.number)")
                .font(.system(.body).weight(.medium))
                .foregroundStyle(.secondary)
            Text(skipped.title)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(skipped.reasonLabel)
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// The live transcript for one PR.
struct TranscriptView: View {
    @ObservedObject var review: PRReview
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(review.name) #\(review.number)").font(.headline)
                    Text(review.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if review.items.isEmpty {
                            Text(review.state == .running ? "Waiting for first event…"
                                                          : "No output yet. Press Run.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        ForEach(Array(review.items.enumerated()), id: \.offset) { idx, item in
                            ItemView(item: item).id(idx)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .onChange(of: review.items.count) { _, count in
                    if count > 0 { withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) } }
                }
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
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(.callout, design: .monospaced)).bold()
                    if let command, !command.isEmpty {
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))

        case .toolResult(_, let isError):
            HStack(spacing: 6) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "arrow.turn.down.right")
                    .foregroundStyle(isError ? .red : .secondary)
                Text(isError ? "tool error" : "tool result")
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .secondary)
            }

        case .finished(let success, let summary):
            VStack(alignment: .leading, spacing: 4) {
                Label(success ? "Review complete" : "Review failed",
                      systemImage: success ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(success ? .green : .red)
                if !summary.isEmpty {
                    MarkdownView(summary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill((success ? Color.green : Color.red).opacity(0.08)))
        }
    }
}

// Tiny placeholder (avoids depending on macOS 14 ContentUnavailableView).
struct ContentUnavailable: View {
    let text: String
    var body: some View {
        VStack { Spacer(); Text(text).foregroundStyle(.secondary); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Auto-review inbox

// The list of completed auto-reviews, each dismissed manually. In-memory only.
struct InboxView: View {
    @EnvironmentObject var model: AppModel
    @State private var viewing: InboxEntry?

    var body: some View {
        if model.inbox.isEmpty {
            ContentUnavailable(text: "No auto-reviews yet. Reviews run by auto-review show up here.")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("\(model.inbox.count) awaiting dismissal")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss all") { model.dismissAll() }
                        .controlSize(.small)
                }
                .padding(12)
                Divider()
                // A List — not ScrollView { LazyVStack } — on purpose. The rows host
                // AppKit-backed controls (`.link` / `.borderless` buttons), and those
                // inside a LazyVStack drive SwiftUI's lazy size-estimation
                // (LazyStack.measureEstimates) into a non-terminating layout-invalidation
                // loop (100% CPU) once the list is scrolled. List virtualizes rows with a
                // stable, non-lazy-estimate layout and hosts the same controls safely —
                // it's what the live-queue sidebar uses for the same reason.
                List {
                    ForEach(model.inbox) { entry in
                        InboxRow(entry: entry, onView: { viewing = entry })
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .sheet(item: $viewing) { entry in InboxTranscriptSheet(entry: entry) }
        }
    }
}

// One completed-review card: verdict, re-review tag, timestamp, and dismiss.
struct InboxRow: View {
    let entry: InboxEntry
    let onView: () -> Void
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.name) #\(entry.number)")
                        .font(.system(.body).weight(.semibold))
                    Text(entry.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if entry.isReReview {
                        Label("re-review · \(reReasonLabel)", systemImage: "arrow.clockwise")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Label(entry.verdict.label, systemImage: entry.verdict.symbol)
                    .font(.caption).foregroundStyle(entry.verdict.tint).labelStyle(.titleAndIcon)
                Button { model.dismiss(entry) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Dismiss")
            }
            HStack(spacing: 14) {
                Text(entry.finishedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                Button("View transcript", action: onView).buttonStyle(.link).controlSize(.small)
                if let url = URL(string: entry.url) {
                    Button("Open on GitHub") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.link).controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }

    private var reReasonLabel: String {
        entry.reason == "new_commits_since_changes_requested"
            ? "new commits since changes-requested" : "prior review not approved"
    }
}

// The stored transcript for one completed auto-review, in a sheet.
struct InboxTranscriptSheet: View {
    let entry: InboxEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.name) #\(entry.number)").font(.headline)
                    Text(entry.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Label(entry.verdict.label, systemImage: entry.verdict.symbol)
                    .foregroundStyle(entry.verdict.tint)
                Button("Done") { dismiss() }
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if entry.items.isEmpty {
                        Text("No transcript captured.").foregroundStyle(.secondary).padding(.top, 8)
                    }
                    ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                        ItemView(item: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .frame(width: 720, height: 560)
    }
}
