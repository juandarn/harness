#!/usr/bin/env bash
# Shared bats helpers: pipe fixture JSON into a hook and build restricted PATHs.

# shellcheck disable=SC2034
SCRIPTS="$BATS_TEST_DIRNAME/../plugin/claude-code/scripts"
GATES="$BATS_TEST_DIRNAME/../plugin/claude-code/gates"

# run_hook <script> <json>: pipes the JSON to the script; stderr is merged into $output.
run_hook() {
  run bash -c 'printf "%s" "$1" | "$2"' _ "$2" "$1"
}

# run_hook_with_path <path-dir> <script> <json>: same, with PATH restricted to one directory.
run_hook_with_path() {
  run env -i HOME="$HOME" PATH="$1" bash -c 'printf "%s" "$1" | bash "$2"' _ "$3" "$2"
}

# tool_path <exclude...>: a dir of symlinks to the tools the hooks need, minus the excluded ones.
tool_path() {
  local dir tool src
  dir="$(mktemp -d)"
  for tool in bash git python3 jq tr cat dirname mkdir date cut tail head sed awk sort wc rm env find ls; do
    case " $* " in *" $tool "*) continue ;; esac
    src="$(command -v "$tool" 2>/dev/null)" && ln -s "$src" "$dir/$tool"
  done
  printf '%s' "$dir"
}

# new_repo: temp git repo exported as REPO and CLAUDE_PROJECT_DIR.
new_repo() {
  REPO="$(cd "$(mktemp -d)" && pwd -P)"
  git -C "$REPO" init -q
  export CLAUDE_PROJECT_DIR="$REPO"
}

git_commit() { git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty "$@"; }
