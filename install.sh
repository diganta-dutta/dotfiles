#!/usr/bin/env bash
# install.sh — symlink dotfiles + slash-commands into their deployment paths.
#
# Idempotent: safe to run multiple times. Existing real files (not symlinks) at
# the target paths are backed up to <file>.backup-<timestamp>.
#
# Configuration via env vars:
#   AI_PROMPTS_REPO       Path to ai-prompts repo (default: $HOME/code/ai-prompts)
#   CLINE_WORKFLOWS_DIR   Path to Cline workflows dir (default: $HOME/Documents/Cline/Workflows)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AI_PROMPTS_REPO="${AI_PROMPTS_REPO:-$HOME/code/ai-prompts}"

CLAUDE_CMDS_SRC="${AI_PROMPTS_REPO}/slash-commands/claude-code/commands"
CLINE_WF_SRC="${AI_PROMPTS_REPO}/slash-commands/cline/workflows"

CLAUDE_CMDS_DST="${HOME}/.claude/commands"
CLINE_WF_DST="${CLINE_WORKFLOWS_DIR:-${HOME}/Documents/Cline/Workflows}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "${AI_PROMPTS_REPO}" ]]; then
  echo "ai-prompts repo not found at: ${AI_PROMPTS_REPO}"
  echo "Clone it first, or run with: AI_PROMPTS_REPO=/path/to/ai-prompts ./install.sh"
  exit 1
fi

ln_one() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [[ ! -e "${src}" ]]; then
    echo "  skip: ${label} source not found at ${src}"
    return
  fi

  mkdir -p "$(dirname "${dst}")"

  if [[ -L "${dst}" ]]; then
    ln -sfn "${src}" "${dst}"
    echo "  link: ${label}"
  elif [[ -e "${dst}" ]]; then
    mv "${dst}" "${dst}.backup-${TIMESTAMP}"
    ln -s "${src}" "${dst}"
    echo "  link: ${label} (existing file backed up to ${dst}.backup-${TIMESTAMP})"
  else
    ln -s "${src}" "${dst}"
    echo "  link: ${label}"
  fi
}

link_tree() {
  local src_dir="$1"
  local dst_dir="$2"
  local label="$3"

  if [[ ! -d "${src_dir}" ]]; then
    echo "  skip: ${label} source dir not found at ${src_dir}"
    return
  fi

  local found=0
  while IFS= read -r -d '' src; do
    found=1
    local rel=${src#"${src_dir}"/}
    local dst="${dst_dir}/${rel}"

    mkdir -p "$(dirname "${dst}")"

    if [[ -L "${dst}" ]]; then
      ln -sfn "${src}" "${dst}"
      echo "  link: ${label}/${rel}"
    elif [[ -e "${dst}" ]]; then
      mv "${dst}" "${dst}.backup-${TIMESTAMP}"
      ln -s "${src}" "${dst}"
      echo "  link: ${label}/${rel} (existing file backed up)"
    else
      ln -s "${src}" "${dst}"
      echo "  link: ${label}/${rel}"
    fi
  done < <(find "${src_dir}" -type f ! -name '.DS_Store' -print0)

  if [[ ${found} -eq 0 ]]; then
    echo "  skip: ${label} has no files"
  fi
}

echo "Installing Claude Code config from ${REPO_DIR}/claude"
ln_one "${REPO_DIR}/claude/settings.json" "${HOME}/.claude/settings.json" "claude/settings.json -> ~/.claude/settings.json"
ln_one "${REPO_DIR}/claude/CLAUDE.md"     "${HOME}/.claude/CLAUDE.md"     "claude/CLAUDE.md -> ~/.claude/CLAUDE.md"

echo "Installing zsh config from ${REPO_DIR}/zsh"
ln_one "${REPO_DIR}/zsh/zshenv" "${HOME}/.zshenv" "zsh/zshenv -> ~/.zshenv"

echo "ai-prompts repo: ${AI_PROMPTS_REPO}"
echo "Installing Claude Code commands -> ${CLAUDE_CMDS_DST}"
link_tree "${CLAUDE_CMDS_SRC}" "${CLAUDE_CMDS_DST}" "claude-code"

echo "Installing Cline workflows -> ${CLINE_WF_DST}"
link_tree "${CLINE_WF_SRC}" "${CLINE_WF_DST}" "cline"

echo ""
echo "Done."
echo ""
if [[ ! -f "${HOME}/.zshenv.local" ]]; then
  echo "NEXT STEP: ~/.zshenv.local does not exist yet."
  echo "  cp ${REPO_DIR}/zsh/zshenv.local.example ~/.zshenv.local"
  echo "  chmod 600 ~/.zshenv.local"
  echo "  # then edit ~/.zshenv.local with real secret values"
fi
