#!/usr/bin/env bash
set -euo pipefail

# 从脚本位置推导源仓，便于仓库整体移动 / clone 到别处后仍正确（与 uninstall.sh 一致）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$SRC/SKILL.md" ]; then
  echo "错误：$SRC/SKILL.md 不存在，先创建 SKILL.md" >&2
  exit 1
fi

for dest in "$HOME/.claude/skills/starks" "$HOME/.codex/skills/starks"; do
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    cur="$(readlink "$dest")"
    if [ "$cur" = "$SRC" ]; then
      echo "已是正确软链，跳过: $dest -> $cur"
    else
      echo "警告：$dest 已是软链但指向 $cur（非 $SRC），未改动" >&2
    fi
  elif [ -e "$dest" ]; then
    echo "警告：$dest 已存在且非软链，未改动" >&2
  else
    ln -s "$SRC" "$dest"
    echo "已建软链: $dest -> $SRC"
  fi
done

echo "--- 验证 ---"
for dest in "$HOME/.claude/skills/starks" "$HOME/.codex/skills/starks"; do
  if [ -f "$dest/SKILL.md" ]; then
    echo "OK: $dest/SKILL.md 可达"
  else
    echo "FAIL: $dest/SKILL.md 不可达" >&2
  fi
done
