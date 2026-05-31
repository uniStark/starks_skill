#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

removed_count=0
skipped_count=0
missing_count=0
error_count=0

# 解析为物理路径，消除父目录软链导致的 latent 失配（与 install.sh 的字面 SRC 兼容）
phys() { ( cd "$1" 2>/dev/null && pwd -P ); }

process() {
  local dest="$1"

  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "missing: $dest"
    missing_count=$((missing_count + 1))
    return
  fi

  if [ -L "$dest" ]; then
    local target
    target="$(readlink "$dest")"
    if [ "$target" = "$SRC" ] || { [ -n "$(phys "$target")" ] && [ "$(phys "$target")" = "$(phys "$SRC")" ]; }; then
      if [ -n "${DRY_RUN:-}" ]; then
        echo "would remove: $dest -> $target"
        removed_count=$((removed_count + 1))
      else
        if rm "$dest"; then
          echo "removed: $dest -> $target"
          removed_count=$((removed_count + 1))
        else
          echo "error removing: $dest" >&2
          error_count=$((error_count + 1))
        fi
      fi
    else
      echo "skip (points elsewhere -> $target): $dest"
      skipped_count=$((skipped_count + 1))
    fi
    return
  fi

  echo "skip (not a symlink): $dest"
  skipped_count=$((skipped_count + 1))
}

process "$HOME/.claude/skills/starks"
process "$HOME/.codex/skills/starks"

echo "summary: removed=$removed_count skipped=$skipped_count missing=$missing_count error=$error_count${DRY_RUN:+ (dry-run)}"

if [ "$error_count" -gt 0 ]; then
  exit 1
fi
