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
