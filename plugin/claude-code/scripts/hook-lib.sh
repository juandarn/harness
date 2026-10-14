#!/usr/bin/env bash
# Shared helpers for harness hook scripts (bash 3.2 compatible). Every gate fails closed.

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export HARNESS_ROOT

# Blocking exit for PreToolUse/Stop: stderr is fed back to the model, exit 2 cannot be ignored.
hook_block() {
  printf 'harness: %s\n' "$*" >&2
  exit 2
}

hook_require_jq() {
  command -v jq >/dev/null 2>&1 || hook_block "jq is required by harness hooks and is missing (brew install jq) — blocking instead of skipping."
}

# Reads stdin into INPUT and blocks unless it is valid JSON.
hook_read_json() {
  hook_require_jq
  INPUT="$(cat)"
  printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || hook_block "hook input is not valid JSON — blocking instead of guessing."
}

# PreToolUse permission decision (deny or ask) on stdout, same shape as the delegation gate; exits 0.
hook_decision() {
  jq -n --arg d "$1" --arg reason "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$reason}}'
  exit 0
}

# Start of a shell command plus any wrappers: sudo/command/time/exec, `env` with options
# (-u NAME, -i) and NAME=value assignments, and bare NAME=value assignments.
HOOK_ASSIGN=$'[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|\'[^\']*\'|[^[:space:]]*)'
HOOK_ENV_OPT="(-[uCS][[:space:]]+[^[:space:]]+|--(unset|chdir|split-string)[[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?|-[A-Za-z0-9]+|${HOOK_ASSIGN})"
HOOK_CMD_PREFIX="(^|[;&|(\`{])[[:space:]]*((sudo|command|time|exec|${HOOK_ASSIGN}|env([[:space:]]+${HOOK_ENV_OPT})*)[[:space:]]+)*"

hook_field() { printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null; }

hook_project_dir() {
  local dir="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$dir" ] || dir="$(hook_field '.cwd // empty')"
  printf '%s' "${dir:-$PWD}"
}

hook_safe_id() { printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_'; }

# .harness/<kind> under the project dir, git-ignored via its own .gitignore.
hook_harness_subdir() {
  local d
  d="$(hook_project_dir)/.harness/$1"
  mkdir -p "$d" 2>/dev/null || return 1
  [ -f "$d/.gitignore" ] || printf '*\n' > "$d/.gitignore" 2>/dev/null
  printf '%s' "$d"
}

# Nearest existing ancestor of a path (a Write may target a directory that does not exist yet).
hook_existing_dir() {
  local d
  d="$(dirname -- "$1")"
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do d="$(dirname -- "$d")"; done
  printf '%s' "$d"
}

hook_repo_root() { git -C "$(hook_existing_dir "$1")" rev-parse --show-toplevel 2>/dev/null; }

# 0 when the path (relative to its repo root) is production source: a code file that is not a
# test, fixture, doc or harness artifact. Config, docs and data files are never source.
hook_is_source_path() {
  local p="/$1" lower base
  lower="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  base="${lower##*/}"
  case "$lower" in
    */.harness/*|*/.claude/*|*/docs/*|*/doc/*|*/node_modules/*|*/vendor/*|*/fixtures/*|*/testdata/*) return 1 ;;
    */test/*|*/tests/*|*/__tests__/*|*/spec/*|*/specs/*|*/e2e/*) return 1 ;;
  esac
  case "$base" in
    test_*|*_test.*|*.test.*|*.spec.*|*_spec.*|conftest.py|*.bats) return 1 ;;
    *test.kt|*tests.kt|*test.java|*tests.java|*test.scala|*spec.kt|*spec.scala) return 1 ;;
  esac
  case "$base" in
    *.go|*.kt|*.kts|*.java|*.scala|*.groovy|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.rb|*.rs|*.php \
    |*.c|*.h|*.cc|*.cpp|*.hpp|*.cs|*.swift|*.sh|*.bash|*.zsh|*.lua) return 0 ;;
  esac
  return 1
}

# Path of the edited file relative to its repo root; symlinked prefixes (/var -> /private/var) are resolved.
hook_relpath() {
  local file="$1" root="$2" dir real full
  dir="$(hook_existing_dir "$file")"
  real="$(cd "$dir" 2>/dev/null && pwd -P)"
  full="${real:-$dir}${file#"$dir"}"
  case "$full" in "$root"/*) printf '%s' "${full#"$root"/}" ;; *) printf '%s' "$full" ;; esac
}

# Per-session turn state file (subagent spawn count, agents: N override, workflow go-ahead).
hook_turn_state() {
  local d sid
  d="$(hook_harness_subdir state)" || return 1
  sid="$(hook_safe_id "$(hook_field '.session_id // empty')")"
  printf '%s/%s.turn' "$d" "${sid:-nosession}"
}

# Directory a git command runs in: `git -C <dir>` wins, then a leading `cd <dir>`, else the default.
hook_cmd_dir() {
  local cmd="${1//$'\n'/;}" dir="$2" target="" cd_re c_re
  cd_re='(^|[;&|][[:space:]]*)cd[[:space:]]+"?([^;&|"[:space:]]+)'
  c_re='git[[:space:]]+-C[[:space:]]+"?([^"[:space:]]+)'
  if [[ "$cmd" =~ $c_re ]]; then target="${BASH_REMATCH[1]}"
  elif [[ "$cmd" =~ $cd_re ]]; then target="${BASH_REMATCH[2]}"; fi
  if [ -n "$target" ]; then
    target="${target/#\~/$HOME}"
    case "$target" in /*) ;; *) target="$dir/$target" ;; esac
    [ -d "$target" ] && dir="$target"
  fi
  printf '%s' "$dir"
}
