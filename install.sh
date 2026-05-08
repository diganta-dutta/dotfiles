#!/usr/bin/env bash
# install.sh — symlink slash-commands from the ai-prompts repo into Claude Code
# and Cline deployment paths.
#
# Idempotent: safe to run multiple times. Existing real files (not symlinks) at
# the target paths are backed up to <file>.backup-<timestamp>.
#
# Configuration via env vars:
#   AI_PROMPTS_REPO       Path to ai-prompts repo (default: $HOME/code/ai-prompts)
#   CLINE_WORKFLOWS_DIR   Path to Cline workflows dir (default: $HOME/Documents/Cline/Workflows)

set -euo pipefail

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

link_files() {
  local src_dir="$1"
  local dst_dir="$2"
  local label="$3"

  if [[ ! -d "${src_dir}" ]]; then
    echo "  skip: ${label} source dir not found at ${src_dir}"
    return
  fi

  mkdir -p "${dst_dir}"

  shopt -s nullglob
  local files=( "${src_dir}"/*.md )
  shopt -u nullglob

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "  skip: ${label} has no .md files"
    return
  fi

  for src in "${files[@]}"; do
    local name; name="$(basename "${src}")"
    local dst="${dst_dir}/${name}"

    if [[ -L "${dst}" ]]; then
      ln -sfn "${src}" "${dst}"
      echo "  link: ${label}/${name}"
    elif [[ -e "${dst}" ]]; then
      mv "${dst}" "${dst}.backup-${TIMESTAMP}"
      ln -s "${src}" "${dst}"
      echo "  link: ${label}/${name} (existing file backed up)"
    else
      ln -s "${src}" "${dst}"
      echo "  link: ${label}/${name}"
    fi
  done
}

echo "ai-prompts repo: ${AI_PROMPTS_REPO}"
echo "Installing Claude Code commands -> ${CLAUDE_CMDS_DST}"
link_files "${CLAUDE_CMDS_SRC}" "${CLAUDE_CMDS_DST}" "claude-code"

echo "Installing Cline workflows -> ${CLINE_WF_DST}"
link_files "${CLINE_WF_SRC}" "${CLINE_WF_DST}" "cline"

echo "Done."
