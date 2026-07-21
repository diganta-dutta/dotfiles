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

ensure_zshrc_stub() {
  # ~/.zshrc is NOT symlinked: installers (nvm, pyenv, gcloud, ...) append PATH
  # blocks to it, and appending through a symlink would write into the repo.
  # Instead ~/.zshrc stays a real per-machine file that sources the shared
  # config from the repo. This only ensures that source line is present; it
  # never rewrites or reorders the user's existing machine-specific lines.
  local repo_zshrc="$1"
  local dst="$2"
  local source_line="source \"${repo_zshrc}\""

  if [[ -L "${dst}" ]]; then
    # A leftover symlink from an older setup — back it up and start a real stub.
    mv "${dst}" "${dst}.backup-${TIMESTAMP}"
    echo "  stub: replaced symlink ${dst} (backed up to ${dst}.backup-${TIMESTAMP})"
  fi

  if [[ ! -e "${dst}" ]]; then
    printf '# ~/.zshrc — per-machine interactive config (NOT tracked in git).\n# Shared interactive config lives in the dotfiles repo, sourced below.\n# Installer PATH lines (nvm, etc.) and machine-specific tweaks go here.\n\n%s\n' "${source_line}" > "${dst}"
    echo "  stub: ${dst} created (sources ${repo_zshrc})"
    return
  fi

  if grep -qF "${repo_zshrc}" "${dst}"; then
    echo "  stub: ${dst} already sources ${repo_zshrc}"
    return
  fi

  printf '\n# Load shared interactive config from dotfiles repo.\n%s\n' "${source_line}" >> "${dst}"
  echo "  stub: ${dst} updated to source ${repo_zshrc}"
}

prune_stale_links() {
  # Remove symlinks under dst_dir that point into src_dir but whose source
  # file no longer exists (e.g. a slash command was deleted upstream). Only
  # touches broken symlinks managed by this script — real files and symlinks
  # pointing elsewhere are left alone.
  local src_dir="$1"
  local dst_dir="$2"
  local label="$3"

  [[ -d "${dst_dir}" ]] || return

  while IFS= read -r -d '' link; do
    local target
    target="$(readlink "${link}")"
    case "${target}" in
      "${src_dir}"/*) ;;   # managed by this script
      *) continue ;;        # points elsewhere — leave it alone
    esac
    if [[ ! -e "${link}" ]]; then
      rm -f "${link}"
      echo "  prune: ${label}/${link#"${dst_dir}"/} (source removed)"
    fi
  done < <(find "${dst_dir}" -type l -print0)
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
ensure_zshrc_stub "${REPO_DIR}/zsh/zshrc" "${HOME}/.zshrc"

echo "ai-prompts repo: ${AI_PROMPTS_REPO}"
echo "Installing Claude Code commands -> ${CLAUDE_CMDS_DST}"
prune_stale_links "${CLAUDE_CMDS_SRC}" "${CLAUDE_CMDS_DST}" "claude-code"
link_tree "${CLAUDE_CMDS_SRC}" "${CLAUDE_CMDS_DST}" "claude-code"

echo "Installing Cline workflows -> ${CLINE_WF_DST}"
prune_stale_links "${CLINE_WF_SRC}" "${CLINE_WF_DST}" "cline"
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
