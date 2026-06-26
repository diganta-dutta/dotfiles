# Review Queue

Menu-bar macOS app that batch-runs Claude Code `/review-pr` reviews across your
GitHub repos. A thin SwiftUI front-end over `review-queue` (a bash workhorse) and
a stream-json parser. Discovers PRs awaiting your review, lets you deselect a
subset, then runs the reviews — serial by default — streaming each one live.

It can also run **unattended**: turn on Auto-review and it polls on an interval,
reviews every eligible PR, and drops each result (verdict + transcript) into an
in-memory **inbox** you dismiss manually. The menu-bar item badges the count of
undismissed results. On a GitHub rate limit it pauses, surfaces the reason and
resume time, and resumes on its own.

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

### Auto-review

Toggle **Auto-review** in the header (or the menu-bar menu) and pick an interval.
On each tick it runs discovery (skipping the git-pull preamble — too heavy to run
every interval) and reviews every eligible PR unattended. The posted verdict
(approved / changes requested / commented) is read back from GitHub via
`--verdict`, not guessed from the transcript, and each result lands in the
**Auto-review inbox** tab: verdict, timestamp, a re-review tag when applicable,
the captured transcript (View transcript), and Open on GitHub. The inbox is
in-memory only — results survive refreshes but not a quit — and entries clear
only when you dismiss them. The menu-bar badge shows the undismissed count.

Reviews post as **formal reviews** with whatever verdict `/review-pr` decides
(including approve/request-changes) — there is no comment-only clamp and no
pre-post staging. The inbox is an after-the-fact record, not an approval gate.

While Auto-review is on the app holds a `userInitiatedAllowingIdleSystemSleep`
activity assertion so the poll timer keeps firing on a **locked** Mac; a
*sleeping* Mac is intentionally allowed to suspend it.

On a GitHub rate limit, discovery (and verdict reads) pause: an amber banner
shows the resume time (from `--rate-reset`, or a 2-minute fallback for secondary
limits the API doesn't report), and a one-shot timer resumes automatically.
**Resume now** overrides it.

Env overrides: `REVIEW_QUEUE_BIN` (backend path), `LAUNCH_CLAUDE_BIN` (preamble
path), `CODE_ROOT` (checkout root), `REVIEW_QUEUE_NO_AUTO_REFRESH=1` (boot the UI
without running the preamble/discovery).

## Usage (backend CLI)

The GUI is optional; `review-queue` works standalone.

```bash
./review-queue --list-json        # {eligible:[...], skipped:[...]} on stdout, diagnostics on stderr
./review-queue --run <pr-url>     # one review, stream-json events on stdout; exit code = claude's
./review-queue --verdict <pr-url> # {"state":...,"submitted_at":...} — my latest review on this PR
./review-queue --rate-reset       # epoch when exhausted gh rate limits recover (empty if none)
```

`--verdict` emits my most-recent review `state` (`APPROVED` /
`CHANGES_REQUESTED` / `COMMENTED` / `DISMISSED` / `NONE`); the app calls it after
an auto-run to record the posted verdict. `--rate-reset` prints the latest reset
epoch among currently-exhausted REST resources (nothing if none are exhausted —
e.g. a secondary limit). Neither invokes claude.

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

`claude -p` authenticates from the macOS keychain (`Claude Code-credentials`),
the same credential an interactive `claude` uses. Two failure modes to know about:

**Inherited session env.** A `claude -p` spawned with another Claude Code
session's environment (`ANTHROPIC_*`, `CLAUDE_CODE_*`, `CLAUDECODE`) tries to
authenticate as a *nested* session and fails with
`401 Invalid authentication credentials`. The app guards against this:
`ProcessRunner.pinnedEnvironment()` strips every `CLAUDE_*` / `ANTHROPIC_*` /
`CLAUDECODE` variable before spawning, so reviews authenticate as a clean
keychain login no matter how the app (or a terminal that launched it) was
started. Note this deliberately also removes `ANTHROPIC_API_KEY` — if you ever
want to drive the app with an explicit API-key env var instead of the keychain,
that key must be exempted from the scrub.

**Token validity.** OAuth access tokens expire on their own; a `401` with no
config change usually means the token lapsed. Re-auth from a normal Terminal
(`claude auth`, or run `claude` once interactively), then `claude -p "say ok"`
should succeed.

**Recommended for auto-review: a long-lived token.** Because auto-review runs
unattended, it shouldn't depend on short-lived-OAuth refresh timing. Run
`claude setup-token` (requires a Claude subscription) once to install a
long-lived token in the keychain; spawned `claude -p` reads it automatically (no
env var needed, so the scrub above doesn't touch it), and unattended runs stop
failing whenever a session token would otherwise have expired.
