# dotfiles

Personal machine config: Claude Code + Cline settings, zsh env, and two menu-bar
apps. `install.sh` symlinks the config into place; the apps build into
`~/Applications` via their own scripts.

## Layout

```
dotfiles/
├── install.sh                 # symlink config + slash-commands into deployment paths
├── claude/
│   ├── settings.json          # -> ~/.claude/settings.json
│   ├── CLAUDE.md              # -> ~/.claude/CLAUDE.md (global instructions)
│   ├── launch/                # "Claude Launcher" — git-pull/refresh then open Claude
│   └── review-queue-app/      # "Review Queue" — batch Claude Code PR reviews (see its README)
└── zsh/
    ├── zshenv                 # -> ~/.zshenv
    └── zshenv.local.example   # template for per-machine secrets (~/.zshenv.local)
```

## install.sh

Symlinks `claude/settings.json`, `claude/CLAUDE.md`, and `zsh/zshenv` into `$HOME`,
and links the slash-commands/workflows from the separate
[ai-prompts](https://github.com/) repo into Claude Code and Cline. Idempotent;
real files at target paths are backed up to `<file>.backup-<timestamp>`, and
stale managed symlinks are pruned.

Clone ai-prompts first (it's the source of the slash-commands):

```bash
git clone <ai-prompts-repo-url> ~/code/ai-prompts
git clone <dotfiles-repo-url>   ~/code/dotfiles
cd ~/code/dotfiles && ./install.sh
```

Env overrides: `AI_PROMPTS_REPO` (default `~/code/ai-prompts`),
`CLINE_WORKFLOWS_DIR` (default `~/Documents/Cline/Workflows`).

Re-run any time ai-prompts gains commands. First run prints a next-step to create
`~/.zshenv.local` (per-machine secrets; git-ignored, never committed).

Verify:

```bash
ls -la ~/.claude/commands/ | grep '\->'        # symlinks into ai-prompts
ls -la ~/Documents/Cline/Workflows/ | grep '\->'
```

## Apps

Both are LSUIElement (menu-bar / no dock) bundles built from scratch by their
`make-*-app.sh` scripts into `~/Applications`. `install.sh` does **not** build
them — run the make script once after cloning, and again after editing.

**Claude Launcher** (`claude/launch/`) — on launch, fast-forwards the dotfiles +
ai-prompts repos, fetches/ff's every other repo under `~/code`, re-runs
`install.sh`, then opens Claude. Build:

```bash
claude/launch/make-launcher-app.sh
claude/launch/launch-claude.sh --no-open   # test the sync step without opening Claude
```

**Review Queue** (`claude/review-queue-app/`) — discovers PRs awaiting your review
and runs Claude Code `/review-pr` over a selected subset, streaming each review
live. Build and usage in
[claude/review-queue-app/README.md](claude/review-queue-app/README.md).
