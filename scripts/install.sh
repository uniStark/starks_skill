#!/usr/bin/env bash
set -euo pipefail

# 从脚本位置推导源仓，便于仓库整体移动 / clone 到别处后仍正确（与 uninstall.sh 一致）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd -P)"

if [ ! -f "$SRC/SKILL.md" ]; then
  echo "错误：$SRC/SKILL.md 不存在，先创建 SKILL.md" >&2
  exit 1
fi

if [ -z "${HOME:-}" ]; then
  echo "错误：HOME 未设置，无法确定 skill 安装目录" >&2
  exit 1
fi

if [ -n "${CODEX_HOME:-}" ]; then
  CODEX_DEST="$CODEX_HOME/skills/starks"
else
  CODEX_DEST="$HOME/.agents/skills/starks"
fi

destinations=(
  "$HOME/.claude/skills/starks"
  "$CODEX_DEST"
)

link_points_to_source() {
  local dest="$1"
  local resolved

  [ -L "$dest" ] || return 1
  resolved="$(cd "$dest" 2>/dev/null && pwd -P)" || return 1
  [ "$resolved" = "$SRC" ]
}

for dest in "${destinations[@]}"; do
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    cur="$(readlink "$dest")"
    if link_points_to_source "$dest"; then
      echo "已是正确软链，跳过: $dest -> $cur"
    else
      echo "警告：$dest 已是软链但指向 ${cur}（非 ${SRC}），未改动" >&2
    fi
  elif [ -e "$dest" ]; then
    echo "警告：$dest 已存在且非软链，未改动" >&2
  else
    ln -s "$SRC" "$dest"
    echo "已建软链: $dest -> $SRC"
  fi
done

echo "--- 验证 ---"
verification_failures=0
for dest in "${destinations[@]}"; do
  if link_points_to_source "$dest" && [ -f "$dest/SKILL.md" ]; then
    echo "OK: $dest/SKILL.md 指向本仓且可达"
  else
    echo "FAIL: $dest 未正确指向本仓，或 SKILL.md 不可达" >&2
    verification_failures=$((verification_failures + 1))
  fi
done

if [ "$verification_failures" -gt 0 ]; then
  exit 1
fi

# 新入口全部验证后，清理由本仓安装的其它已知 Codex 软链，避免同名 skill 重复加载。
for previous_codex_dest in "$HOME/.agents/skills/starks" "$HOME/.codex/skills/starks"; do
  if [ "$previous_codex_dest" != "$CODEX_DEST" ] && link_points_to_source "$previous_codex_dest"; then
    rm "$previous_codex_dest"
    echo "已迁移并移除旧软链: $previous_codex_dest"
  fi
done
