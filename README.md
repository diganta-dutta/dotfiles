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
    ├── zshenv                 # -> ~/.zshenv (symlinked)
    ├── zshenv.local.example   # template for per-machine secrets (~/.zshenv.local)
    └── zshrc                  # shared interactive config, sourced by a ~/.zshrc stub
```

### zsh layout: symlink vs. stub

`~/.zshenv` is **symlinked** — nothing appends to it, so a symlink is safe and
edits to the repo take effect everywhere immediately.

`~/.zshrc` is **not** symlinked. Installers (nvm, pyenv, gcloud, rustup, …)
append PATH blocks to `~/.zshrc`, and appending through a symlink would write
into the repo. So `~/.zshrc` stays a real per-machine file that just sources
the shared `zsh/zshrc`; `install.sh` adds that source line if it's missing.
Shared interactive config (prompt, aliases, functions, completions) goes in
`zsh/zshrc`; machine-specific tweaks and installer PATH lines live directly in
`~/.zshrc`. (No `~/.zshrc.local` needed — `~/.zshrc` itself is the per-machine
file. Env vars/PATH that non-interactive shells must see still belong in
`zsh/zshenv`.)

## install.sh

Symlinks `claude/settings.json`, `claude/CLAUDE.md`, and `zsh/zshenv` into `$HOME`,
ensures `~/.zshrc` sources `zsh/zshrc` (see zsh layout above),
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
