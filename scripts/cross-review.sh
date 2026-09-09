#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PROMPT_FILE="$SRC/prompts/cross-review.md"
ENV_FILE="$SRC/.env"
TIMEOUT_RUNNER="$SRC/scripts/run_with_timeout.py"
TMP_BASE="${TMPDIR:-/tmp}"
if [[ ! -d "$TMP_BASE" ]]; then
  echo "错误：TMPDIR 不存在或不是目录: $TMP_BASE" >&2
  exit 1
fi
TMP_BASE="$(cd "$TMP_BASE" && pwd -P)"
RUN_DIR=""
PLAN_FILE=""
REVIEW_INPUT_FILE=""

cleanup() {
  if [[ -n "$RUN_DIR" && -d "$RUN_DIR" ]]; then
    run_parent="$(cd "$(dirname "$RUN_DIR")" && pwd -P)"
    run_name="$(basename "$RUN_DIR")"
    if [[ "$run_parent" == "$TMP_BASE" && "$run_name" == starks-cross-review.* ]]; then
      rm -rf "$RUN_DIR"
    else
      echo "警告：拒绝清理非预期临时目录: $RUN_DIR" >&2
    fi
  fi
}
trap cleanup EXIT

usage() {
  cat >&2 <<'EOF'
Usage: scripts/cross-review.sh <codex|claude> [repo-dir]

Read the plan from stdin and send it to the selected reviewer engine.
EOF
  exit 2
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

load_dotenv_key() {
  local key="$1"
  local line value

  [[ -f "$ENV_FILE" ]] || return 0
  if printenv "$key" >/dev/null 2>&1; then
    return 0
  fi

  line="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 0
  value="$(trim "${line#*=}")"
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  export "$key=$value"
}

run_with_timeout() {
  local seconds="$1"
  local input_file="$2"
  shift 2
  STARKS_CROSS_REVIEW=1 python3 "$TIMEOUT_RUNNER" "$seconds" "$@" < "$input_file"
}

toml_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

add_unique_path() {
  local candidate="$1"
  local existing
  for existing in ${skill_paths[@]+"${skill_paths[@]}"}; do
    [[ "$existing" == "$candidate" ]] && return 0
  done
  skill_paths+=("$candidate")
}

add_skill_location() {
  local location="$1"
  local physical

  [[ -f "$location/SKILL.md" ]] || return 0

  # Codex 文档版本曾分别要求 skill 目录或 SKILL.md 文件路径；两种都传，
  # 让 path-based disable 在新旧 CLI 上都能命中。
  add_unique_path "$location"
  add_unique_path "$location/SKILL.md"
  physical="$(cd "$location" && pwd -P)"
  add_unique_path "$physical"
  add_unique_path "$physical/SKILL.md"
}

[[ "$#" -ge 1 && "$#" -le 2 ]] || usage
engine="$1"
case "$engine" in
  codex|claude) ;;
  *) usage ;;
esac

if [[ -n "${STARKS_CROSS_REVIEW:-}" ]]; then
  echo "错误：检测到 STARKS_CROSS_REVIEW，拒绝递归启动跨模型互审" >&2
  exit 2
fi

repo_dir="${2:-$PWD}"
if [[ ! -d "$repo_dir" ]]; then
  echo "错误：仓库目录不存在: $repo_dir" >&2
  exit 2
fi
repo_dir="$(cd "$repo_dir" && pwd -P)"

if [[ ! -s "$PROMPT_FILE" ]]; then
  echo "错误：reviewer prompt 不存在或为空: $PROMPT_FILE" >&2
  exit 2
fi
if [[ -t 0 ]]; then
  echo "错误：请通过 stdin 传入待审查方案" >&2
  exit 2
fi
if ! command -v "$engine" >/dev/null 2>&1; then
  echo "错误：找不到 reviewer CLI: $engine" >&2
  exit 127
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "错误：找不到 python3，无法安全执行 reviewer watchdog" >&2
  exit 127
fi
if [[ ! -s "$TIMEOUT_RUNNER" ]]; then
  echo "错误：watchdog runner 不存在或为空: $TIMEOUT_RUNNER" >&2
  exit 2
fi

for key in STARKS_REVIEW_MODEL_CODEX STARKS_REVIEW_MODEL_CLAUDE STARKS_REVIEW_TIMEOUT_SECONDS; do
  load_dotenv_key "$key"
done

timeout_seconds="${STARKS_REVIEW_TIMEOUT_SECONDS:-600}"
case "$timeout_seconds" in
  ''|*[!0-9]*)
    echo "错误：STARKS_REVIEW_TIMEOUT_SECONDS 必须是正整数" >&2
    exit 2
    ;;
  0)
    echo "错误：STARKS_REVIEW_TIMEOUT_SECONDS 必须大于 0" >&2
    exit 2
    ;;
esac

review_prompt="$(<"$PROMPT_FILE")"

if ! RUN_DIR="$(mktemp -d "$TMP_BASE/starks-cross-review.XXXXXX")" || [[ -z "$RUN_DIR" ]]; then
  echo "错误：无法创建跨模型互审临时目录" >&2
  exit 1
fi
PLAN_FILE="$RUN_DIR/plan.txt"
REVIEW_WORKSPACE="$RUN_DIR/reviewer-workspace"
mkdir -p "$REVIEW_WORKSPACE"
cat > "$PLAN_FILE"
if ! grep -q '[^[:space:]]' "$PLAN_FILE"; then
  echo "错误：待审查方案不能为空" >&2
  exit 2
fi
REVIEW_INPUT_FILE="$RUN_DIR/review-input.txt"
{
  printf '%s\n' "$review_prompt"
  printf '\n--- BEGIN UNTRUSTED PLAN DATA ---\n'
  cat "$PLAN_FILE"
} > "$REVIEW_INPUT_FILE"

if [[ "$engine" == "codex" ]]; then
  skill_paths=()
  add_skill_location "$SRC"
  if [[ -n "${CODEX_HOME:-}" ]]; then
    add_skill_location "$CODEX_HOME/skills/starks"
  fi
  if [[ -n "${HOME:-}" ]]; then
    add_skill_location "$HOME/.agents/skills/starks"
    add_skill_location "$HOME/.codex/skills/starks"
  fi

  skills_config='['
  separator=''
  for skill_path in "${skill_paths[@]}"; do
    escaped_path="$(toml_escape "$skill_path")"
    skills_config+="${separator}{path=\"${escaped_path}\",enabled=false}"
    separator=','
  done
  skills_config+=']'

  command=(
    codex exec
    --sandbox read-only
    --disable shell_tool
    --ignore-user-config
    --ignore-rules
    --ephemeral
    --skip-git-repo-check
    -C "$REVIEW_WORKSPACE"
    -c "skills.config=$skills_config"
    -c 'shell_environment_policy.inherit="none"'
    -c 'agents.enabled=false'
    -c 'apps._default.enabled=false'
    -c 'tools.web_search=false'
    -c 'tools.view_image=false'
  )
  if [[ -n "${STARKS_REVIEW_MODEL_CODEX:-}" ]]; then
    command+=(-m "$STARKS_REVIEW_MODEL_CODEX")
  fi
  # `-` 明确要求 Codex 把组合后的 reviewer 指令与方案都从 stdin 读取。
  command+=(-)

  cd "$REVIEW_WORKSPACE"
  run_with_timeout "$timeout_seconds" "$REVIEW_INPUT_FILE" "${command[@]}"
else
  command=(
    claude -p
    --safe-mode
    --disable-slash-commands
    --tools ''
    --no-session-persistence
  )
  if [[ -n "${STARKS_REVIEW_MODEL_CLAUDE:-}" ]]; then
    command+=(--model "$STARKS_REVIEW_MODEL_CLAUDE")
  fi
  cd "$REVIEW_WORKSPACE"
  run_with_timeout "$timeout_seconds" "$REVIEW_INPUT_FILE" "${command[@]}"
fi
