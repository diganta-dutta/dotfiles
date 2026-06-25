# Review Queue

Menu-bar macOS app that batch-runs Claude Code `/review-pr` reviews across your
GitHub repos. A thin SwiftUI front-end over `review-queue` (a bash workhorse) and
a stream-json parser. Discovers PRs awaiting your review, lets you deselect a
subset, then runs the reviews — serial by default — streaming each one live.

## Components

```
review-queue                 backend: discovery + per-PR execution (bash)
Sources/                     the app
  ReviewStreamParser.swift   stream-json (NDJSON) -> render items; partial-line safe
  Backend.swift              Paths, Process shell-out, PRItem (Foundation only)
  Models.swift               AppModel + PRReview (state, run queue)
  ContentView.swift          checklist sidebar + live transcript pane
  AppDelegate.swift, main.swift   NSStatusItem + window bootstrap
make-review-queue-app.sh     builds ~/Applications/Review Queue.app
tests/                       run-tests.sh, Smoke.swift
STREAM-SCHEMA.md             the stream-json event schema this parses
```

## Prerequisites

- `gh` (authenticated: `gh auth status`), `jq`, `git`, and `claude` on `PATH`.
  `claude` is expected at `~/.local/bin`; gh/jq at Homebrew. The app pins
  `PATH=~/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin` for spawned
  processes.
- Swift toolchain (`xcrun swiftc`), macOS 14+.
- A local checkout of each repo under `~/code/<repo-name>` — PRs without one are
  skipped by discovery.

## Build & install

```bash
./make-review-queue-app.sh          # compiles Sources/*.swift -> ~/Applications/Review Queue.app
open "$HOME/Applications/Review Queue.app"
```

Rebuild after any source edit. The bundle is rebuilt from scratch each run and
registered with Launch Services.

## Usage (GUI)

1. Menu-bar checklist icon → **Open Review Queue** (also opens on first launch).
2. On open it runs the shared git-pull preamble (`claude/launch/launch-claude.sh
   --no-open`) then `review-queue --list-json`, populating the checklist. Toggle
   the preamble off in the header if you don't want the pull.
3. Deselect any PRs to skip. Pick concurrency (Serial / 2 / 3 — serial is kindest
   to rate limits).
4. **Run N selected** spawns `review-queue --run <url>` per PR. Click a PR to
   watch its review stream live; per-PR state goes queued → running → done/failed.
5. **Open in Desktop** on a PR opens Terminal in that repo and runs `claude`
   interactively (no `-p`) seeded with `/review-pr <url>`.

Env overrides: `REVIEW_QUEUE_BIN` (backend path), `LAUNCH_CLAUDE_BIN` (preamble
path), `CODE_ROOT` (checkout root), `REVIEW_QUEUE_NO_AUTO_REFRESH=1` (boot the UI
without running the preamble/discovery).

## Usage (backend CLI)

The GUI is optional; `review-queue` works standalone.

```bash
./review-queue --list-json        # {eligible:[...], skipped:[...]} on stdout, diagnostics on stderr
./review-queue --run <pr-url>     # one review, stream-json events on stdout; exit code = claude's
```

`--list-json` emits a single object: `{ "eligible": [...], "skipped": [...] }`,
each entry `{repo, name, number, url, title, reason}`. Every open PR where you're
a requested reviewer lands in exactly one bucket. Eligible `reason` is
`never_reviewed`, `new_commits_since_changes_requested`, or
`prior_review_not_approved`; skipped `reason` is `no_local_checkout`,
`ci_not_green`, `approved`, or `changes_requested_no_new_commits`. CI gating is
via `gh pr checks`; the re-review decision compares your last review's state and
commit against the PR head. `CODE_ROOT` and `SLASH_CMD` (default `/review-pr`)
are env-overridable.

## Tests

```bash
tests/run-tests.sh                # backend smoke: review-queue --list-json -> [PRItem] (no GUI, no claude)
```

The parser self-test and its fixture were removed after dev (the only realistic
fixture was a capture of a private PR). Regenerate a sanitized capture if you want
that regression test back.

## Note on auth

`claude -p` reads keychain OAuth like an interactive terminal — but **fails with
a 401 when spawned from inside another Claude Code session**. Launch the app from
Finder/`open` (a normal login context), not from within a Claude session, or
reviews will all fail with no events.
