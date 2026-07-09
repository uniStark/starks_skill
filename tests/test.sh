#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
FAKE_BIN="$SCRIPT_DIR/fixtures/fake-bin"
TMP_BASE="${TMPDIR:-/tmp}"
if ! TMP_ROOT="$(mktemp -d "$TMP_BASE/starks-tests.XXXXXX")" || [[ -z "$TMP_ROOT" ]]; then
  printf 'FAIL: unable to create isolated test directory\n' >&2
  exit 1
fi
failures=0
checks=0

cleanup() {
  case "$TMP_ROOT" in
    "$TMP_BASE"/starks-tests.*) rm -rf "$TMP_ROOT" ;;
    *) printf 'REFUSE cleanup outside test prefix: %s\n' "$TMP_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

pass() {
  checks=$((checks + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (expected=$expected actual=$actual)"
  fi
}

assert_contains() {
  local text="$1"
  local needle="$2"
  local label="$3"
  if [[ "$text" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (missing: $needle)"
  fi
}

assert_not_contains() {
  local text="$1"
  local needle="$2"
  local label="$3"
  if [[ "$text" == *"$needle"* ]]; then
    fail "$label (unexpected: $needle)"
  else
    pass "$label"
  fi
}

assert_file_line() {
  local file="$1"
  local line="$2"
  local label="$3"
  if [[ -f "$file" ]] && grep -Fxq -- "$line" "$file"; then
    pass "$label"
  else
    fail "$label (missing line: $line)"
  fi
}

assert_file_not_line() {
  local file="$1"
  local line="$2"
  local label="$3"
  if [[ -f "$file" ]] && grep -Fxq -- "$line" "$file"; then
    fail "$label (unexpected line: $line)"
  else
    pass "$label"
  fi
}

run_install_case() {
  local case_name="$1"
  local foreign_target="$2"
  local home="$TMP_ROOT/install-$case_name-home"
  local output rc target
  mkdir -p "$home/.claude/skills" "$home/.codex/skills"
  ln -s "$foreign_target" "$home/.claude/skills/starks"

  if output="$(HOME="$home" "$BASH" "$SRC/scripts/install.sh" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi

  assert_eq "0" "$rc" "install preserves $case_name symlink without crashing"
  assert_not_contains "$output" "unbound variable" "install $case_name path has no nounset failure"
  target="$(readlink "$home/.claude/skills/starks")"
  assert_eq "$foreign_target" "$target" "install does not replace $case_name symlink"
  if [[ -L "$home/.codex/skills/starks" ]]; then
    pass "install continues after $case_name symlink"
  else
    fail "install continues after $case_name symlink"
  fi
}

run_install_regression() {
  local existing_target="$TMP_ROOT/existing-foreign-target"
  mkdir -p "$existing_target"
  run_install_case "foreign" "$existing_target"
  run_install_case "broken" "$TMP_ROOT/missing-foreign-target"
}

run_cross_review_codex() {
  local capture="$TMP_ROOT/codex-capture"
  local plan='PLAN-CODEX-完整输入'
  local rc=0
  mkdir -p "$capture"

  if [[ ! -x "$SRC/scripts/cross-review.sh" ]]; then
    fail "cross-review wrapper exists and is executable"
    return
  fi

  if printf '%s' "$plan" | env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" \
    STARKS_REVIEW_MODEL_CODEX= \
    STARKS_REVIEW_MODEL_CLAUDE= \
    STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" codex "$SRC"; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "0" "$rc" "codex wrapper exits successfully with fake CLI"
  assert_file_line "$capture/args" "--sandbox" "codex reviewer sets sandbox flag"
  assert_file_line "$capture/args" "read-only" "codex reviewer is read-only"
  assert_file_not_line "$capture/args" "--strict-config" "codex reviewer tolerates unrelated legacy user config"
  assert_file_line "$capture/args" "--ignore-user-config" "codex reviewer isolates user config and hooks"
  assert_file_line "$capture/args" "--ignore-rules" "codex reviewer ignores user and project execpolicy"
  assert_file_line "$capture/args" "--ephemeral" "codex reviewer does not persist a session"
  assert_file_not_line "$capture/args" "-m" "codex omits model flag when unset"
  if grep -Fq 'skills.config=[{path=' "$capture/args" 2>/dev/null; then
    pass "codex disables starks by path"
  else
    fail "codex disables starks by path"
  fi
  if grep -Fq 'name="starks"' "$capture/args" 2>/dev/null; then
    fail "codex config does not use obsolete name key"
  else
    pass "codex config does not use obsolete name key"
  fi
  assert_eq "$plan" "$(cat "$capture/stdin" 2>/dev/null)" "codex receives the complete plan on stdin"
  assert_eq "1" "$(cat "$capture/guard" 2>/dev/null)" "codex receives recursion guard"
  assert_eq "$SRC" "$(cat "$capture/cwd" 2>/dev/null)" "codex reviewer runs in target repo"

  capture="$TMP_ROOT/codex-model-capture"
  mkdir -p "$capture"
  printf '%s' "$plan" | env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" \
    STARKS_REVIEW_MODEL_CODEX=gpt-test-reviewer \
    STARKS_REVIEW_MODEL_CLAUDE= \
    STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1
  assert_file_line "$capture/args" "-m" "codex passes model flag when configured"
  assert_file_line "$capture/args" "gpt-test-reviewer" "codex passes configured model"
}

run_cross_review_claude() {
  local capture="$TMP_ROOT/claude-capture"
  local plan='PLAN-CLAUDE-完整输入'
  local rc=0
  mkdir -p "$capture"

  if [[ ! -x "$SRC/scripts/cross-review.sh" ]]; then
    fail "claude cross-review wrapper exists and is executable"
    return
  fi

  if printf '%s' "$plan" | env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" \
    STARKS_REVIEW_MODEL_CODEX= \
    STARKS_REVIEW_MODEL_CLAUDE= \
    STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" claude "$SRC"; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "0" "$rc" "claude wrapper exits successfully with fake CLI"
  assert_file_line "$capture/args" "--tools" "claude reviewer explicitly configures tools"
  assert_file_line "$capture/args" "--safe-mode" "claude reviewer disables customizations and hooks"
  assert_file_line "$capture/args" "--disable-slash-commands" "claude reviewer disables skills"
  assert_file_not_line "$capture/args" "--permission-mode" "claude reviewer avoids plan-mode tool execution"
  assert_file_line "$capture/args" "--no-session-persistence" "claude reviewer leaves no resumable session"
  assert_file_not_line "$capture/args" "--model" "claude omits model flag when unset"
  assert_eq "$plan" "$(cat "$capture/stdin" 2>/dev/null)" "claude receives the complete plan on stdin"
  assert_eq "1" "$(cat "$capture/guard" 2>/dev/null)" "claude receives recursion guard"
  assert_eq "$SRC" "$(cat "$capture/cwd" 2>/dev/null)" "claude reviewer runs in target repo"

  capture="$TMP_ROOT/claude-model-capture"
  mkdir -p "$capture"
  printf '%s' "$plan" | env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" \
    STARKS_REVIEW_MODEL_CODEX= \
    STARKS_REVIEW_MODEL_CLAUDE=claude-test-reviewer \
    STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" claude "$SRC" >/dev/null 2>&1
  assert_file_line "$capture/args" "--model" "claude passes model flag when configured"
  assert_file_line "$capture/args" "claude-test-reviewer" "claude passes configured model"
}

run_cross_review_failures() {
  local capture="$TMP_ROOT/failure-capture"
  local rc
  mkdir -p "$capture" "$TMP_ROOT/reviewer-home"

  if printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" STARKS_REVIEW_MODEL_CODEX= STARKS_REVIEW_MODEL_CLAUDE= \
    STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" invalid "$SRC" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "2" "$rc" "wrapper rejects an invalid reviewer engine"

  if printf 'plan' | env PATH="/usr/bin:/bin" HOME="$TMP_ROOT/reviewer-home" \
    STARKS_REVIEW_MODEL_CODEX= STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "127" "$rc" "wrapper reports a missing reviewer CLI"

  if printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" FAKE_EXIT_CODE=23 STARKS_REVIEW_MODEL_CODEX= \
    STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "23" "$rc" "wrapper preserves reviewer failure status"

  if printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" STARKS_REVIEW_MODEL_CODEX= STARKS_REVIEW_MODEL_CLAUDE= \
    STARKS_REVIEW_TIMEOUT_SECONDS=invalid \
    "$BASH" "$SRC/scripts/cross-review.sh" claude "$SRC" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "2" "$rc" "wrapper rejects an invalid timeout"

  if printf '   \n' | env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" STARKS_REVIEW_MODEL_CODEX= STARKS_REVIEW_MODEL_CLAUDE= \
    STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "2" "$rc" "wrapper rejects an empty plan"

  if printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" STARKS_CROSS_REVIEW=1 STARKS_REVIEW_MODEL_CODEX= \
    STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "2" "$rc" "wrapper refuses recursive cross-review invocation"
}

run_cross_review_path_and_timeout() {
  local foreign_home="$TMP_ROOT/foreign-home"
  local foreign_skill="$TMP_ROOT/foreign-starks"
  local capture="$TMP_ROOT/foreign-capture"
  local timeout_capture="$TMP_ROOT/timeout-capture"
  local foreign_physical rc started elapsed
  mkdir -p "$foreign_home/.codex/skills" "$foreign_skill" "$capture" "$timeout_capture"
  printf '%s\n' '---' 'name: starks' 'description: foreign fixture' '---' > "$foreign_skill/SKILL.md"
  ln -s "$foreign_skill" "$foreign_home/.codex/skills/starks"
  foreign_physical="$(cd "$foreign_skill" && pwd -P)"

  printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$foreign_home" CAPTURE_DIR="$capture" \
    STARKS_REVIEW_MODEL_CODEX= STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1
  if grep -Fq "$foreign_home/.codex/skills/starks" "$capture/args" && \
    grep -Fq "$foreign_physical" "$capture/args" && grep -Fq "$SRC" "$capture/args"; then
    pass "codex disables source, installed, and physical starks paths"
  else
    fail "codex disables source, installed, and physical starks paths"
  fi

  started="$(date +%s)"
  grandchild_file="$TMP_ROOT/grandchild.pid"
  if printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$timeout_capture" FAKE_CHILD_PID_FILE="$grandchild_file" FAKE_IGNORE_TERM=1 \
    STARKS_REVIEW_MODEL_CODEX= \
    STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=1 \
    "$BASH" "$SRC/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  elapsed=$(( $(date +%s) - started ))
  assert_eq "124" "$rc" "wrapper returns timeout status without external timeout tools"
  if [[ "$elapsed" -lt 5 ]]; then
    pass "portable timeout stops a hung reviewer promptly"
  else
    fail "portable timeout stops a hung reviewer promptly (elapsed=${elapsed}s)"
  fi
  grandchild_pid="$(cat "$grandchild_file" 2>/dev/null || true)"
  if [[ -n "$grandchild_pid" ]] && kill -0 "$grandchild_pid" >/dev/null 2>&1; then
    fail "portable timeout terminates reviewer descendants"
    kill "$grandchild_pid" >/dev/null 2>&1 || true
  else
    pass "portable timeout terminates reviewer descendants"
  fi

  relative_parent="$TMP_ROOT/relative-parent"
  relative_capture="$TMP_ROOT/relative-capture"
  mkdir -p "$relative_parent/relative-tmp" "$relative_capture"
  (
    cd "$relative_parent" || exit 1
    printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
      TMPDIR=relative-tmp CAPTURE_DIR="$relative_capture" STARKS_REVIEW_MODEL_CODEX= \
      STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=600 \
      "$BASH" "$SRC/scripts/cross-review.sh" claude "$SRC" >/dev/null 2>&1
  )
  relative_leftovers="$(find "$relative_parent/relative-tmp" -mindepth 1 -maxdepth 1 -type d -name 'starks-cross-review.*' | wc -l | tr -d ' ')"
  assert_eq "0" "$relative_leftovers" "relative TMPDIR is resolved and cleaned safely"
}

run_dotenv_precedence() {
  local skill_copy="$TMP_ROOT/dotenv-skill"
  local capture="$TMP_ROOT/dotenv-capture"
  local override_capture="$TMP_ROOT/dotenv-override-capture"
  local empty_capture="$TMP_ROOT/dotenv-empty-capture"
  local injection_capture="$TMP_ROOT/dotenv-injection-capture"
  local injection_marker="$TMP_ROOT/dotenv-command-ran"
  mkdir -p "$skill_copy/scripts" "$skill_copy/prompts" "$capture" "$override_capture" "$empty_capture" "$injection_capture"
  cp "$SRC/scripts/cross-review.sh" "$skill_copy/scripts/cross-review.sh"
  cp "$SRC/scripts/run_with_timeout.py" "$skill_copy/scripts/run_with_timeout.py"
  cp "$SRC/prompts/cross-review.md" "$skill_copy/prompts/cross-review.md"
  chmod +x "$skill_copy/scripts/cross-review.sh"
  printf '%s\n' \
    'STARKS_REVIEW_MODEL_CODEX=dotenv-reviewer' \
    'STARKS_REVIEW_TIMEOUT_SECONDS=600' > "$skill_copy/.env"

  printf 'plan' | env -u STARKS_REVIEW_MODEL_CODEX -u STARKS_REVIEW_TIMEOUT_SECONDS \
    PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" CAPTURE_DIR="$capture" \
    STARKS_REVIEW_MODEL_CLAUDE= \
    "$BASH" "$skill_copy/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1
  assert_file_line "$capture/args" "dotenv-reviewer" "wrapper loads reviewer model from .env"

  printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$override_capture" STARKS_REVIEW_MODEL_CODEX=exported-reviewer \
    STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$skill_copy/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1
  assert_file_line "$override_capture/args" "exported-reviewer" "exported reviewer model overrides .env"
  assert_file_not_line "$override_capture/args" "dotenv-reviewer" "dotenv does not replace exported reviewer model"

  printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$empty_capture" STARKS_REVIEW_MODEL_CODEX= \
    STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$skill_copy/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1
  assert_file_not_line "$empty_capture/args" "-m" "an explicitly empty model suppresses .env model selection"

  printf '%s\n' \
    "STARKS_REVIEW_MODEL_CODEX=\$(touch $injection_marker)" \
    'STARKS_REVIEW_TIMEOUT_SECONDS=600' > "$skill_copy/.env"
  printf 'plan' | env -u STARKS_REVIEW_MODEL_CODEX -u STARKS_REVIEW_TIMEOUT_SECONDS \
    PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" CAPTURE_DIR="$injection_capture" \
    STARKS_REVIEW_MODEL_CLAUDE= \
    "$BASH" "$skill_copy/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1
  if [[ ! -e "$injection_marker" ]]; then
    pass "dotenv values are parsed as data, not executed"
  else
    fail "dotenv values are parsed as data, not executed"
  fi
}

run_nested_shell_regression() {
  local capture="$TMP_ROOT/nested-capture"
  local nested_output rc
  mkdir -p "$capture"

  if nested_output="$(env PATH="$FAKE_BIN:$PATH" HOME="$TMP_ROOT/reviewer-home" \
    CAPTURE_DIR="$capture" FAKE_STDOUT=LIVE_REVIEW STARKS_REVIEW_MODEL_CODEX= \
    STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" -c 'result="$(printf plan | "$1" "$2/scripts/cross-review.sh" claude "$2")"; printf "AFTER:%s" "$result"' \
    _ "$BASH" "$SRC" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "0" "$rc" "wrapper does not terminate a calling shell during command substitution"
  assert_eq "AFTER:LIVE_REVIEW" "$nested_output" "wrapper preserves reviewer stdout in command substitution"
}

run_contract_checks() {
  local skill readme readme_zh spec memory
  skill="$(cat "$SRC/SKILL.md")"
  readme="$(cat "$SRC/README.md")"
  readme_zh="$(cat "$SRC/README.zh-CN.md")"
  spec="$(cat "$SRC/prompts/spec-review.md")"
  memory="$(cat "$SRC/prompts/memory-writer.md")"

  assert_contains "$skill" "scripts/cross-review.sh" "skill delegates fragile cross-review invocation to a script"
  assert_not_contains "$skill" 'name="starks"' "skill does not document obsolete Codex name config"
  assert_not_contains "$readme" '$STARKS_REVIEW_MODEL"' "README has no obsolete unsplit review-model variable"
  assert_not_contains "$skill" "纯查询 / 概念解释" "non-work queries are outside starks task tiers"
  assert_not_contains "$readme" "concept explanation" "English README keeps non-work queries outside task tiers"
  assert_not_contains "$readme_zh" "纯查询 / 概念解释" "Chinese README keeps non-work queries outside task tiers"
  assert_contains "$skill" "平台规则与用户授权" "native memory writes are policy and authorization gated"
  assert_contains "$skill" "可用并发槽位" "parallel fan-out respects platform capacity"
  assert_not_contains "$spec" "git diff / 测试" "spec reviewer does not classify tests as read-only"
  assert_not_contains "$memory" "一律用 shell 写入" "memory writer is not tied to one machine's write hook"
  assert_not_contains "$skill" "绕开拦 Write 的 hook" "skill does not instruct agents to bypass local hooks"
  if [[ -s "$SRC/agents/openai.yaml" ]]; then
    pass "Codex agents/openai.yaml metadata exists"
  else
    fail "Codex agents/openai.yaml metadata exists"
  fi
}

run_install_regression
run_cross_review_codex
run_cross_review_claude
run_cross_review_failures
run_cross_review_path_and_timeout
run_dotenv_precedence
run_nested_shell_regression
run_contract_checks

if [[ "$failures" -ne 0 ]]; then
  printf 'tests FAIL: %s/%s checks failed\n' "$failures" "$checks" >&2
  exit 1
fi

printf 'tests OK: %s checks\n' "$checks"
