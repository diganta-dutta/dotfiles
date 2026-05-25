# User-level instructions

## Jira

For any Jira task (viewing tickets, listing issues, sprint info, etc.), use the `jira` CLI (ankitpokhrel/jira-cli, installed at /opt/homebrew/bin/jira) instead of the web UI, MCP servers, or REST API.

Common commands:
- `jira issue view <KEY>` — view a ticket
- `jira issue list -a$(jira me) -s~Done` — my open issues
- `jira sprint list --current` — current sprint
- `jira epic list` / `jira board list` / `jira project list`

Read-only `jira` commands are pre-approved in settings.json. Write commands (`create`, `edit`, `move`, `delete`, `comment`) will prompt — that's intentional, don't try to work around it.

If a Jira action fails, surface the raw `jira` error rather than falling back to other tools.

## Git commits

Do not use `$(cat <<'EOF' ... EOF)` heredoc command substitution for commit messages — it triggers permission prompts even when `git commit *` and `cat *` are individually allowed.

Instead, use one of:
- `git commit -m "subject" -m "body paragraph 1" -m "body paragraph 2"` — multiple `-m` flags become separate paragraphs in the commit message.
- For longer or more complex messages, write to a file and use `-F`:
  ```
  Write the message to .git/COMMIT_EDITMSG via the Write tool, then run:
  git commit -F .git/COMMIT_EDITMSG
  ```

Both forms match `Bash(git commit *)` cleanly without command substitution.

## Ad-hoc scripts

When you need to write a temporary one-off Python script to perform analysis, parse data, or run a calculation, always:

1. Name the file with a `claude-` prefix
2. Place it under `~/.claude/scratch/` (absolute: `/Users/diganta/.claude/scratch/`)

Example: `/Users/diganta/.claude/scratch/claude-scan-transcripts.py`, not `/tmp/scan-transcripts.py`.

Run with `python3 /Users/diganta/.claude/scratch/claude-<name>.py [args]`. The directory exists; do not run `mkdir` to recreate it.

**Why:** Only `Bash(python3 /Users/diganta/.claude/scratch/claude-*.py *)` is pre-approved. Any other Python invocation — different path, missing prefix, full-path venv binary — will trigger a permission prompt every invocation. `~/.claude/scratch/` is per-user (not world-writable like `/tmp/`), which closes the "another local process plants a script" attack vector.

**How to apply:** Whenever you choose a path for a temp Python script — whether via Write, `cat > file`, or shell heredoc — start the filename with `claude-` and put it in `~/.claude/scratch/`. This applies only to scripts *you* author; it does not apply to data files, output captures, or files the user has named. If the user has an existing project script (e.g. `scripts/foo.py`), run it as-is and accept the prompt rather than copying it into the scratch directory.

**Do not use `python -c "..."` for non-trivial code.** It bypasses the scratch-dir naming convention and is functionally equivalent to running an arbitrary `.py` file (it triggers a permission prompt every time, and the payload is harder to review/iterate on than a file). For anything beyond a single trivial expression (e.g. `python3 -c "import sys; print(sys.version)"`), write a `claude-*.py` file to `~/.claude/scratch/` and run it. Same applies to `python -m <module>` invocations of arbitrary modules.

## Git invocation

Do not prefix git commands with `git -C <path>` when `<path>` matches the current working directory. The allowlist in settings.json matches `Bash(git <subcommand> *)` patterns by prefix, so `git -C /repo status` does not match `Bash(git status*)` and triggers a permission prompt. Run `git <subcommand>` from the current working directory instead.

Use `git -C <path>` only when operating on a *different* repo than the cwd. The same principle applies to `cd <current-dir> && git ...` — never prepend a redundant directory switch.
