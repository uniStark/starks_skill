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
  mkdir -p "$home/.claude/skills" "$home/.agents/skills"
  ln -s "$foreign_target" "$home/.claude/skills/starks"

  if output="$(env -u CODEX_HOME HOME="$home" "$BASH" "$SRC/scripts/install.sh" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi

  assert_eq "1" "$rc" "install reports failed verification for $case_name symlink"
  assert_not_contains "$output" "unbound variable" "install $case_name path has no nounset failure"
  assert_contains "$output" "FAIL:" "install prints verification failure for $case_name symlink"
  target="$(readlink "$home/.claude/skills/starks")"
  assert_eq "$foreign_target" "$target" "install does not replace $case_name symlink"
  if [[ -L "$home/.agents/skills/starks" ]]; then
    pass "install continues after $case_name symlink"
  else
    fail "install continues after $case_name symlink"
  fi
}

run_install_regression() {
  local existing_target="$TMP_ROOT/existing-foreign-target"
  local default_home="$TMP_ROOT/install-default-home"
  local custom_home="$TMP_ROOT/install-custom-home"
  local custom_codex_home="$TMP_ROOT/custom-codex-home"
  local output rc
  mkdir -p "$existing_target"
  run_install_case "foreign" "$existing_target"
  run_install_case "broken" "$TMP_ROOT/missing-foreign-target"

  mkdir -p "$default_home/.codex/skills"
  ln -s "$SRC" "$default_home/.codex/skills/starks"
  if output="$(env -u CODEX_HOME HOME="$default_home" "$BASH" "$SRC/scripts/install.sh" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "0" "$rc" "default install verifies successfully"
  if [[ -L "$default_home/.agents/skills/starks" ]]; then
    pass "default Codex install uses the cross-client skill root"
  else
    fail "default Codex install uses the cross-client skill root"
  fi
  if [[ ! -e "$default_home/.codex/skills/starks" && ! -L "$default_home/.codex/skills/starks" ]]; then
    pass "default install removes its verified legacy Codex symlink"
  else
    fail "default install removes its verified legacy Codex symlink"
  fi

  mkdir -p "$custom_home/.agents/skills" "$custom_home/.codex/skills"
  ln -s "$SRC" "$custom_home/.agents/skills/starks"
  ln -s "$existing_target" "$custom_home/.codex/skills/starks"
  if output="$(HOME="$custom_home" CODEX_HOME="$custom_codex_home" "$BASH" "$SRC/scripts/install.sh" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "0" "$rc" "custom CODEX_HOME install verifies successfully"
  if [[ -L "$custom_codex_home/skills/starks" ]]; then
    pass "installer respects custom CODEX_HOME"
  else
    fail "installer respects custom CODEX_HOME"
  fi
  if [[ ! -e "$custom_home/.agents/skills/starks" && ! -L "$custom_home/.agents/skills/starks" ]]; then
    pass "custom CODEX_HOME install removes its inactive verified link"
  else
    fail "custom CODEX_HOME install removes its inactive verified link"
  fi
  if [[ "$(readlink "$custom_home/.codex/skills/starks" 2>/dev/null)" == "$existing_target" ]]; then
    pass "installer preserves an inactive Codex link that points elsewhere"
  else
    fail "installer preserves an inactive Codex link that points elsewhere"
  fi
}

run_uninstall_regression() {
  local home="$TMP_ROOT/uninstall-home"
  local codex_home="$TMP_ROOT/uninstall-codex-home"
  local foreign_target="$TMP_ROOT/uninstall-foreign-target"
  local dest rc
  mkdir -p "$home/.claude/skills" "$home/.agents/skills" "$home/.codex/skills" \
    "$codex_home/skills" "$foreign_target"
  ln -s "$SRC" "$home/.claude/skills/starks"
  ln -s "$SRC" "$home/.agents/skills/starks"
  ln -s "$foreign_target" "$home/.codex/skills/starks"
  ln -s "$SRC" "$codex_home/skills/starks"

  if HOME="$home" CODEX_HOME="$codex_home" "$BASH" "$SRC/scripts/uninstall.sh" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  assert_eq "0" "$rc" "uninstall handles custom and recognized Codex roots"
  for dest in "$home/.claude/skills/starks" "$home/.agents/skills/starks" "$codex_home/skills/starks"; do
    if [[ ! -e "$dest" && ! -L "$dest" ]]; then
      pass "uninstall removes verified project link: $dest"
    else
      fail "uninstall removes verified project link: $dest"
    fi
  done
  if [[ "$(readlink "$home/.codex/skills/starks" 2>/dev/null)" == "$foreign_target" ]]; then
    pass "uninstall preserves a Codex link that points elsewhere"
  else
    fail "uninstall preserves a Codex link that points elsewhere"
  fi
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
  assert_file_line "$capture/args" "--disable" "codex reviewer disables a feature"
  assert_file_line "$capture/args" "shell_tool" "codex reviewer disables shell tools"
  assert_file_not_line "$capture/args" "--strict-config" "codex reviewer tolerates unrelated legacy user config"
  assert_file_line "$capture/args" "--ignore-user-config" "codex reviewer isolates user config and hooks"
  assert_file_line "$capture/args" "--ignore-rules" "codex reviewer ignores user and project execpolicy"
  assert_file_line "$capture/args" "--ephemeral" "codex reviewer does not persist a session"
  assert_file_line "$capture/args" "--skip-git-repo-check" "codex reviewer uses an isolated non-repository workspace"
  assert_file_line "$capture/args" 'shell_environment_policy.inherit="none"' "codex reviewer strips child-process environment"
  assert_file_line "$capture/args" "agents.enabled=false" "codex reviewer disables sub-agents"
  assert_file_line "$capture/args" "apps._default.enabled=false" "codex reviewer disables apps"
  assert_file_line "$capture/args" "tools.web_search=false" "codex reviewer disables web search"
  assert_file_line "$capture/args" "tools.view_image=false" "codex reviewer disables image tools"
  assert_file_not_line "$capture/args" "-m" "codex omits model flag when unset"
  if grep -Fq 'skills.config=[{path=' "$capture/args" 2>/dev/null; then
    pass "codex disables starks by path"
  else
    fail "codex disables starks by path"
  fi
  if grep -Fq "$SRC/SKILL.md" "$capture/args" 2>/dev/null; then
    pass "codex disables the current CLI's SKILL.md entrypoint form"
  else
    fail "codex disables the current CLI's SKILL.md entrypoint form"
  fi
  if grep -Fq 'name="starks"' "$capture/args" 2>/dev/null; then
    fail "codex config does not use obsolete name key"
  else
    pass "codex config does not use obsolete name key"
  fi
  assert_contains "$(cat "$capture/stdin" 2>/dev/null)" "--- BEGIN UNTRUSTED PLAN DATA ---" "codex stdin separates instructions from untrusted plan data"
  assert_contains "$(cat "$capture/stdin" 2>/dev/null)" "$plan" "codex receives the complete plan on stdin"
  assert_file_line "$capture/args" "-" "codex explicitly reads its request from stdin"
  assert_eq "1" "$(cat "$capture/guard" 2>/dev/null)" "codex receives recursion guard"
  if [[ "$(cat "$capture/cwd" 2>/dev/null)" == "$SRC" ]]; then
    fail "codex reviewer is isolated from the target repo"
  else
    pass "codex reviewer is isolated from the target repo"
  fi

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
  assert_contains "$(cat "$capture/stdin" 2>/dev/null)" "--- BEGIN UNTRUSTED PLAN DATA ---" "claude stdin separates instructions from untrusted plan data"
  assert_contains "$(cat "$capture/stdin" 2>/dev/null)" "$plan" "claude receives the complete plan on stdin"
  assert_eq "1" "$(cat "$capture/guard" 2>/dev/null)" "claude receives recursion guard"
  if [[ "$(cat "$capture/cwd" 2>/dev/null)" == "$SRC" ]]; then
    fail "claude reviewer is isolated from the target repo"
  else
    pass "claude reviewer is isolated from the target repo"
  fi

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
  local foreign_codex_home="$TMP_ROOT/foreign-codex-home"
  local foreign_skill="$TMP_ROOT/foreign-starks"
  local capture="$TMP_ROOT/foreign-capture"
  local timeout_capture="$TMP_ROOT/timeout-capture"
  local foreign_physical rc started elapsed
  mkdir -p "$foreign_home/.codex/skills" "$foreign_codex_home/skills" "$foreign_skill" "$capture" "$timeout_capture"
  printf '%s\n' '---' 'name: starks' 'description: foreign fixture' '---' > "$foreign_skill/SKILL.md"
  ln -s "$foreign_skill" "$foreign_home/.codex/skills/starks"
  ln -s "$foreign_skill" "$foreign_codex_home/skills/starks"
  foreign_physical="$(cd "$foreign_skill" && pwd -P)"

  printf 'plan' | env PATH="$FAKE_BIN:$PATH" HOME="$foreign_home" CODEX_HOME="$foreign_codex_home" CAPTURE_DIR="$capture" \
    STARKS_REVIEW_MODEL_CODEX= STARKS_REVIEW_MODEL_CLAUDE= STARKS_REVIEW_TIMEOUT_SECONDS=600 \
    "$BASH" "$SRC/scripts/cross-review.sh" codex "$SRC" >/dev/null 2>&1
  if grep -Fq "$foreign_home/.codex/skills/starks/SKILL.md" "$capture/args" && \
    grep -Fq "$foreign_codex_home/skills/starks/SKILL.md" "$capture/args" && \
    grep -Fq "$foreign_physical/SKILL.md" "$capture/args" && grep -Fq "$SRC/SKILL.md" "$capture/args"; then
    pass "codex disables source, custom, legacy, and physical SKILL.md paths"
  else
    fail "codex disables source, custom, legacy, and physical SKILL.md paths"
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
  local skill readme readme_zh runtime pm_ref design review_prompt skill_lines
  skill="$(cat "$SRC/SKILL.md")"
  readme="$(cat "$SRC/README.md")"
  readme_zh="$(cat "$SRC/README.zh-CN.md")"
  runtime="$SRC/references/runtime.md"
  pm_ref="$SRC/references/pm-orchestration.md"
  design="$(cat "$SRC/docs/DESIGN.md")"
  review_prompt="$(cat "$SRC/prompts/cross-review.md")"

  [[ -s "$runtime" ]] && pass "runtime reference exists" || fail "runtime reference exists"
  [[ -s "$pm_ref" ]] && pass "PM reference exists" || fail "PM reference exists"
  assert_contains "$skill" "HARD-GATE" "skill defines HARD-GATE"
  assert_contains "$skill" "references/runtime.md" "skill routes runtime details"
  assert_contains "$skill" "references/pm-orchestration.md" "skill routes PM details"
  assert_contains "$skill" "平台全局默认" "skill documents global model defaults"
  assert_contains "$skill" "思考深度" "skill documents thinking-depth decisions"
  runtime_text="$(cat "$runtime")"
  assert_contains "$runtime_text" "默认继承平台全局默认模型与思考深度" "runtime uses platform defaults"
  assert_contains "$runtime_text" "自行选择子代理的模型与思考深度" "runtime permits PM model decisions"
  assert_contains "$skill" "不触发外部知识库" "skill disables external memory"
  assert_not_contains "$skill$readme$readme_zh$runtime$design" "luna_worker" "no Luna worker references"
  assert_not_contains "$skill$readme$readme_zh$runtime$design" "Obsidian" "no Obsidian references"
  assert_not_contains "$skill$readme$readme_zh$runtime$design" "STARKS_MEMORY" "no memory environment variables"
  assert_not_contains "$skill$readme$readme_zh$runtime$design" "memory-reader" "no memory reader references"
  assert_not_contains "$skill$readme$readme_zh$runtime$design" "memory-writer" "no memory writer references"
  assert_contains "$review_prompt" "不要访问仓库或环境" "cross-review prompt is isolated"
  if ! skill_lines="$(awk 'END { print NR }' "$SRC/SKILL.md")"; then
    fail "skill line count readable"
  elif [[ "$skill_lines" -le 85 ]]; then
    pass "skill entrypoint is concise"
  else
    fail "skill entrypoint is concise (actual=$skill_lines)"
  fi
}

run_install_regression
run_uninstall_regression
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
