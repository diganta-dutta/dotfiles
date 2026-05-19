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
