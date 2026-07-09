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
  shift
  STARKS_CROSS_REVIEW=1 python3 "$TIMEOUT_RUNNER" "$seconds" "$@" < "$PLAN_FILE"
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
cat > "$PLAN_FILE"
if ! grep -q '[^[:space:]]' "$PLAN_FILE"; then
  echo "错误：待审查方案不能为空" >&2
  exit 2
fi

if [[ "$engine" == "codex" ]]; then
  skill_paths=()
  add_unique_path "$SRC"
  installed_skill_path="${HOME:-}/.codex/skills/starks"
  if [[ -n "${HOME:-}" && -f "$installed_skill_path/SKILL.md" ]]; then
    add_unique_path "$installed_skill_path"
    installed_physical="$(cd "$installed_skill_path" && pwd -P)"
    add_unique_path "$installed_physical"
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
    --ignore-user-config
    --ignore-rules
    --ephemeral
    -C "$repo_dir"
    -c "skills.config=$skills_config"
  )
  if ! git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    command+=(--skip-git-repo-check)
  fi
  if [[ -n "${STARKS_REVIEW_MODEL_CODEX:-}" ]]; then
    command+=(-m "$STARKS_REVIEW_MODEL_CODEX")
  fi
  command+=("$review_prompt")

  run_with_timeout "$timeout_seconds" "${command[@]}"
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
  command+=("$review_prompt")

  cd "$repo_dir"
  run_with_timeout "$timeout_seconds" "${command[@]}"
fi
