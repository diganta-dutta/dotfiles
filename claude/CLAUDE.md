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
