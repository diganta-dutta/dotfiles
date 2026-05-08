# dotfiles

Personal machine config. Currently just symlinks slash-commands from the [ai-prompts](https://github.com/) repo into Claude Code and Cline deployment paths.

## Layout

```
dotfiles/
├── README.md
└── install.sh
```

## Prerequisite

Clone the `ai-prompts` repo first:

```bash
git clone <ai-prompts-repo-url> ~/code/ai-prompts
```

If you keep it elsewhere, set `AI_PROMPTS_REPO` when running install:

```bash
AI_PROMPTS_REPO=/path/to/ai-prompts ./install.sh
```

## Install

```bash
git clone <dotfiles-repo-url> ~/dotfiles
cd ~/dotfiles
./install.sh
```

Re-run any time the ai-prompts repo gains new slash-commands. Idempotent.

## Cline workflows path

Default is `~/Documents/Cline/Workflows`. Override if your install differs:

```bash
CLINE_WORKFLOWS_DIR="$HOME/path/to/Cline/Workflows" ./install.sh
```

Find the actual path in Cline's settings panel.

## Verify

```bash
ls -la ~/.claude/commands/ | grep '\->'
ls -la ~/Documents/Cline/Workflows/ | grep '\->'
```

Both should show symlinks pointing into the ai-prompts repo. In Claude Code, type `/` and confirm the prompt names appear. In Cline, the workflows show up in the slash-command picker.

## Workflow

- Edit a prompt in the ai-prompts repo → commit → push.
- Pull on any other workstation → already symlinked, change is live.
- New machine → clone both repos, run `./install.sh`.
