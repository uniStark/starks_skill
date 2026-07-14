#!/usr/bin/env bash
# SKILL.md 结构 smoke lint —— 可被 CI / cron 从任意目录调用。
# 注意：不用 set -e，需收集所有失败项而非遇错即退。
set -uo pipefail

# 从脚本位置定位 SKILL.md，不依赖调用者 cwd。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$SRC/SKILL.md"
PM_REF="$SRC/references/pm-orchestration.md"
MEMORY_REF="$SRC/references/memory.md"

failures=()

# 文件存在性前置检查。
if [[ ! -f "$SKILL" ]]; then
  failures+=("SKILL.md 不存在: $SKILL")
fi

# 检查 1：frontmatter（用 python3 解析，不在 bash 里假解析 YAML）。
if [[ -f "$SKILL" ]]; then
  fm_result="$(python3 - "$SKILL" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

errs = []

lines = text.splitlines()
# 开头必须是 --- ... --- 的 frontmatter。
if not lines or lines[0].strip() != "---":
    errs.append("frontmatter 缺失：文件未以 '---' 开头")
else:
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        errs.append("frontmatter 未闭合：找不到第二个 '---'")
    else:
        block = "\n".join(lines[1:end])
        data = None
        try:
            import yaml
            data = yaml.safe_load(block)
        except ImportError:
            # 无 pyyaml 时退回简单逐行 key: value 解析。
            data = {}
            for ln in block.splitlines():
                if ":" in ln and not ln.lstrip().startswith("#"):
                    k, _, v = ln.partition(":")
                    data[k.strip()] = v.strip()
        if not isinstance(data, dict):
            errs.append("frontmatter 解析结果不是映射(dict)")
        else:
            name = data.get("name")
            if name != "starks":
                errs.append(f"frontmatter name 应为 'starks'，实际为 {name!r}")
            desc = data.get("description")
            if desc is None or str(desc).strip() == "":
                errs.append("frontmatter description 字段为空")

for e in errs:
    print(e)
PY
)"
  if [[ -n "$fm_result" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && failures+=("$line")
    done <<< "$fm_result"
  fi
fi

# 检查 2：结构 smoke —— 关键锚点存在，缺哪个记哪个。
if [[ -f "$SKILL" ]]; then
  anchors=("HARD-GATE" "STARKS_CROSS_REVIEW" "跨模型互审" "记忆收尾" "references/runtime.md" "references/pm-orchestration.md" "references/memory.md" "prompts/memory-reader.md" "Ready" "读取前询问" "写入前询问" "当前直接观察" "最多回炉 2 次" "prompts/spec-review.md" "prompts/code-review.md" "scripts/cross-review.sh" "平台规则" "可用并发槽位")
  for a in "${anchors[@]}"; do
    if ! grep -qF -- "$a" "$SKILL"; then
      failures+=("缺少关键锚点: $a")
    fi
  done
fi

if [[ ! -s "$SRC/references/runtime.md" ]]; then
  failures+=("缺少 runtime reference: references/runtime.md")
fi
if [[ ! -s "$PM_REF" ]]; then
  failures+=("缺少 PM orchestration reference: references/pm-orchestration.md")
fi
if [[ ! -s "$MEMORY_REF" ]]; then
  failures+=("缺少 memory reference: references/memory.md")
fi

# 检查 3：SKILL.md 引用的 prompt 模板必须存在。
for p in cross-review memory-reader memory-writer spec-review code-review; do
  if [[ ! -f "$SRC/prompts/$p.md" ]]; then
    failures+=("缺少 prompt 模板: prompts/$p.md")
  fi
done

# 检查 4：运行脚本和 Codex metadata 必须存在。
for executable in install.sh uninstall.sh lint.sh cross-review.sh; do
  if [[ ! -x "$SRC/scripts/$executable" ]]; then
    failures+=("脚本不存在或不可执行: scripts/$executable")
  fi
done
if [[ ! -s "$SRC/scripts/run_with_timeout.py" ]]; then
  failures+=("缺少 watchdog runner: scripts/run_with_timeout.py")
fi
if [[ ! -s "$SRC/agents/openai.yaml" ]]; then
  failures+=("缺少 Codex metadata: agents/openai.yaml")
else
  for field in display_name short_description default_prompt; do
    if ! grep -qE "^[[:space:]]+${field}:" "$SRC/agents/openai.yaml"; then
      failures+=("agents/openai.yaml 缺少字段: $field")
    fi
  done
  if ! grep -qF '$starks' "$SRC/agents/openai.yaml"; then
    failures+=("agents/openai.yaml default_prompt 未显式引用 \$starks")
  fi
fi

# 检查 5：防 fence 残留 smoke —— 没有任何一行以四个反引号开头。
if [[ -f "$SKILL" ]]; then
  fence_count="$(grep -c '^````' "$SKILL")"
  if [[ "$fence_count" -ne 0 ]]; then
    failures+=("发现 $fence_count 行以四个反引号开头（疑似 fence 残留）")
  fi
fi

# 检查 6：已知语义漂移不能回归。
if grep -qF 'name="starks"' "$SKILL"; then
  failures+=("仍在使用已废弃的 Codex skills.config name 键")
fi
if grep -qF '$STARKS_REVIEW_MODEL"' "$SRC/README.md"; then
  failures+=("README.md 仍在使用未拆分的 STARKS_REVIEW_MODEL")
fi

# 检查 7：shell 语法与行为测试。
shell_files=(
  "$SRC/scripts/install.sh"
  "$SRC/scripts/uninstall.sh"
  "$SRC/scripts/lint.sh"
  "$SRC/scripts/cross-review.sh"
  "$SRC/tests/test.sh"
  "$SRC/tests/fixtures/fake-bin/codex"
  "$SRC/tests/fixtures/fake-bin/claude"
)
if ! "$BASH" -n "${shell_files[@]}"; then
  failures+=("shell 语法检查失败")
fi
if ! python3 -m py_compile "$SRC/scripts/run_with_timeout.py"; then
  failures+=("Python watchdog 语法检查失败")
fi
if ! test_output="$("$BASH" "$SRC/tests/test.sh" 2>&1)"; then
  failures+=("行为测试失败:\n$test_output")
fi

# 汇总输出。
if [[ ${#failures[@]} -ne 0 ]]; then
  echo "lint FAIL (${#failures[@]} 项):"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

echo "lint OK"
exit 0
