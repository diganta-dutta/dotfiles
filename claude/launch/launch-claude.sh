#!/usr/bin/env bash
# launch-claude.sh — pre-launch prep for the Claude desktop app.
#
# For each config repo: auto-stash local changes, fast-forward pull, restore the
# stash. If any repo actually advanced, re-run install.sh to refresh symlinks.
# Then open Claude.app. Failures are reported as warnings and NEVER block the
# launch — you can always start working even offline or mid-conflict.
#
# Usage:
#   launch-claude.sh            # sync, then open Claude
#   launch-claude.sh --no-open  # sync only (for testing); do not open the app
#
# Invoked by ~/Applications/Claude Launcher.app (see make-launcher-app.sh).

set -uo pipefail   # deliberately NOT -e: we handle every error and warn-continue.

# GUI-launched apps get a minimal PATH; pin the tools we need.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

DOTFILES="$HOME/code/dotfiles"
AI_PROMPTS="$HOME/code/ai-prompts"

# Matches install.sh's built-in default ($HOME/code/ai-prompts); set explicitly
# so the launcher stays correct even if that default ever changes.
export AI_PROMPTS_REPO="$AI_PROMPTS"

REPOS=("$DOTFILES" "$AI_PROMPTS")

OPEN_APP=1
[[ "${1:-}" == "--no-open" ]] && OPEN_APP=0

log() { printf '[claude-prep] %s\n' "$*"; }

changed=0

for repo in "${REPOS[@]}"; do
  if [[ ! -d "$repo/.git" ]]; then
    log "WARN: $repo is not a git repo — skipping"
    continue
  fi

  log "Syncing $repo"
  before="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo none)"
  branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD || echo main)"

  # Auto-stash if there are staged or unstaged changes (untracked files don't
  # block a fast-forward, so we leave them in place).
  stashed=0
  if ! git -C "$repo" diff --quiet || ! git -C "$repo" diff --cached --quiet; then
    if git -C "$repo" stash push -u -m "claude-prep auto-stash"; then
      stashed=1
      log "  stashed local changes"
    else
      log "  WARN: stash failed — skipping pull for $repo"
      continue
    fi
  fi

  if git -C "$repo" pull --ff-only origin "$branch"; then
    after="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo none)"
    if [[ "$before" != "$after" ]]; then
      changed=1
      log "  updated ${before:0:8} -> ${after:0:8}"
    else
      log "  already up to date"
    fi
  else
    log "  WARN: pull failed for $repo (offline or divergent history?)"
  fi

  if [[ "$stashed" == 1 ]]; then
    if git -C "$repo" stash pop; then
      log "  restored local changes"
    else
      log "  WARN: stash pop conflict in $repo — changes are safe in 'git stash list'"
    fi
  fi
done

if [[ "$changed" == 1 ]]; then
  if [[ -x "$DOTFILES/install.sh" ]]; then
    log "Repo changes detected — running install.sh"
    "$DOTFILES/install.sh" || log "WARN: install.sh exited non-zero"
  else
    log "WARN: install.sh missing or not executable at $DOTFILES/install.sh"
  fi
else
  log "No repo changes — skipping install.sh"
fi

if [[ "$OPEN_APP" == 1 ]]; then
  log "Launching Claude…"
  open -a "Claude" || log "WARN: could not open Claude.app"
else
  log "--no-open: skipping app launch"
fi
