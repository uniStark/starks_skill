#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd -P)"

removed_count=0
skipped_count=0
missing_count=0
error_count=0

# 解析为物理路径，消除父目录软链导致的 latent 失配（与 install.sh 的字面 SRC 兼容）
phys() { ( cd "$1" 2>/dev/null && pwd -P ); }
resolve_link_target() {
  local dest="$1"
  local target
  target="$(readlink "$dest")"
  if [[ "$target" = /* ]]; then
    phys "$target"
  else
    phys "$(dirname "$dest")/$target"
  fi
}

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
    resolved_target="$(resolve_link_target "$dest")"
    if [ -n "$resolved_target" ] && [ "$resolved_target" = "$(phys "$SRC")" ]; then
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

if [ -z "${HOME:-}" ]; then
  echo "错误：HOME 未设置，无法确定 skill 安装目录" >&2
  exit 1
fi

destinations=("$HOME/.claude/skills/starks")
if [ -n "${CODEX_HOME:-}" ]; then
  destinations+=("$CODEX_HOME/skills/starks")
fi
destinations+=(
  "$HOME/.agents/skills/starks"
  "$HOME/.codex/skills/starks"
)

unique_destinations=()
for dest in "${destinations[@]}"; do
  duplicate=0
  for existing in ${unique_destinations[@]+"${unique_destinations[@]}"}; do
    if [ "$existing" = "$dest" ]; then
      duplicate=1
      break
    fi
  done
  if [ "$duplicate" -eq 0 ]; then
    unique_destinations+=("$dest")
  fi
done

for dest in "${unique_destinations[@]}"; do
  process "$dest"
done

echo "summary: removed=$removed_count skipped=$skipped_count missing=$missing_count error=$error_count${DRY_RUN:+ (dry-run)}"

if [ "$error_count" -gt 0 ]; then
  exit 1
fi
