#!/usr/bin/env bats

load helpers

setup() {
  unset HARNESS_PROTECT_STATE
  HOOK="$SCRIPTS/pre-state-guard.sh"
  new_repo
  HOME="$(cd "$(mktemp -d)" && pwd -P)"
  export HOME
  mkdir -p "$REPO/.harness/state" "$HOME/.claude/projects/-Users-x/memory"
  TRANSCRIPT="$HOME/.claude/projects/-Users-x/abc.jsonl"
  REASON="harness: .harness/state and session transcripts are the hooks' evidence; they are written only by the hooks. Leave them alone."
}

teardown() {
  rm -rf "$REPO" "$HOME" "${FAKE:-}"
}

# file_json <tool> <path> [agent_id] [path key]
file_json() {
  jq -nc --arg t "$1" --arg p "$2" --arg a "${3:-}" --arg k "${4:-file_path}" --arg cwd "$REPO" --arg tp "$TRANSCRIPT" \
    '{session_id: "s1", cwd: $cwd, transcript_path: $tp, tool_name: $t, tool_input: {($k): $p}} + (if $a != "" then {agent_id: $a} else {} end)'
}
bash_json() { jq -nc --arg c "$1" --arg cwd "$REPO" '{session_id: "s1", cwd: $cwd, tool_name: "Bash", tool_input: {command: $c}}'; }
decision() { if [ -z "$output" ]; then echo allow; else echo "$output" | jq -r '.hookSpecificOutput.permissionDecision'; fi; }

# fcheck <allow|deny> <path> [tool]
fcheck() {
  run_hook "$HOOK" "$(file_json "${3:-Write}" "$2")"
  [ "$status" -eq 0 ] || { echo "status $status for: $2 -> $output"; return 1; }
  [ "$(decision)" = "$1" ] || { echo "expected $1, got $(decision) for: $2"; return 1; }
}

# bcheck <allow|deny> <command>
bcheck() {
  run_hook "$HOOK" "$(bash_json "$2")"
  [ "$status" -eq 0 ] || { echo "status $status for: $2 -> $output"; return 1; }
  [ "$(decision)" = "$1" ] || { echo "expected $1, got $(decision) for: $2"; return 1; }
}

@test "with the knob unset or not 1 every call passes untouched, even malformed input" {
  fcheck allow "$REPO/.harness/state/s1.turn"
  bcheck allow 'rm .harness/state/s1.turn'
  run_hook "$HOOK" 'not json'
  [ "$status" -eq 0 ] && [ -z "$output" ]
  export HARNESS_PROTECT_STATE=0
  fcheck allow "$TRANSCRIPT"
  export HARNESS_PROTECT_STATE=""
  bcheck allow 'echo x > .harness/state/s1.turn'
}

@test "with the knob set, unparseable input fails closed and unrelated tools pass" {
  export HARNESS_PROTECT_STATE=1
  run_hook "$HOOK" 'not json'
  [ "$status" -eq 2 ]
  run_hook "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/x/.harness/state/a"}}'
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "file tools are denied on .harness/state with the exact reason and JSON shape" {
  export HARNESS_PROTECT_STATE=1
  for t in Edit Write MultiEdit; do
    run_hook "$HOOK" "$(file_json "$t" "$REPO/.harness/state/s1.turn")"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c .)" = "$(jq -nc --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}')" ]
  done
  run_hook "$HOOK" "$(file_json NotebookEdit "$REPO/.harness/state/n.ipynb" "" notebook_path)"
  [ "$(decision)" = "deny" ]
}

@test "subagent calls get no exemption" {
  export HARNESS_PROTECT_STATE=1
  run_hook "$HOOK" "$(file_json Edit "$REPO/.harness/state/s1.turn" sub-123)"
  [ "$(decision)" = "deny" ]
  run_hook "$HOOK" "$(file_json Write "$TRANSCRIPT" sub-123)"
  [ "$(decision)" = "deny" ]
  run_hook "$HOOK" "$(file_json Write "$REPO/src.py" sub-123)"
  [ "$(decision)" = "allow" ]
}

@test "state paths are caught however they are spelled: relative, .., symlinks, new files, other projects" {
  export HARNESS_PROTECT_STATE=1
  ln -s "$REPO/.harness/state" "$REPO/link"
  ln -s "$REPO/.harness/state/s1.turn" "$REPO/flink"
  mkdir -p "$REPO/src"
  for p in ".harness/state/s1.turn" "./.harness/state/new.turn" "$REPO/src/../.harness/state/s1.turn" "$REPO/link/s1.turn" \
    "$REPO/link/not-yet/there.turn" "$REPO/flink" "$REPO/.harness/state/deep/er/x" "$REPO/.harness/state" "$REPO/.harness/state/"; do
    fcheck deny "$p"
  done
  OTHER="$(mktemp -d)"
  mkdir -p "$OTHER/.harness/state"
  fcheck deny "$OTHER/.harness/state/other.turn"
  rm -rf "$OTHER"
}

@test "neighbours of the state dir stay writable" {
  export HARNESS_PROTECT_STATE=1
  for p in "$REPO/.harness/logs/pre-commit-gate.log" "$REPO/.harness/state.txt" "$REPO/.harness/stateful/x" "$REPO/src/state/a.kt" \
    "$REPO/src/a.py" "$REPO/.gitignore" "$REPO/state/s1.turn" ".harness/logs/x.log"; do
    fcheck allow "$p"
  done
}

@test "session transcripts are protected, memory notes and other .claude files are not" {
  export HARNESS_PROTECT_STATE=1
  mkdir -p "$HOME/.claude/projects/-Users-x/abc/subagents"
  for p in "$TRANSCRIPT" "$HOME/.claude/projects/-Users-x/abc/subagents/agent-1.jsonl" "$HOME/.claude/projects/-Users-y/new.jsonl" \
    "$HOME/.claude/projects/-Users-x/../-Users-x/abc.jsonl"; do
    fcheck deny "$p"
  done
  for p in "$HOME/.claude/projects/-Users-x/memory/MEMORY.md" "$HOME/.claude/projects/-Users-x/memory/note.md" \
    "$HOME/.claude/projects/-Users-x/notes.md" "$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md" "$REPO/data.jsonl"; do
    fcheck allow "$p"
  done
}

@test "the live transcript_path is protected wherever it lives" {
  export HARNESS_PROTECT_STATE=1
  TRANSCRIPT="$REPO/elsewhere.txt"
  fcheck deny "$REPO/elsewhere.txt"
  fcheck allow "$REPO/other.txt"
}

@test "Bash: every write form that touches state or a transcript is denied" {
  export HARNESS_PROTECT_STATE=1
  S=".harness/state/s1.turn"
  T="$HOME/.claude/projects/-Users-x/abc.jsonl"
  for c in "echo '{}' > $S" "echo x >> $REPO/$S" "cat a.json >| $S" "rm $S" "rm -rf .harness/state" "mv a $S" "cp a $S" "cp a .harness/state/" \
    "echo x | tee $S" "touch $S" "truncate -s 0 $S" "dd if=/dev/zero of=$S" "ln -sf /tmp/x $S" "install a .harness/state/" "chmod 000 $S" \
    "rsync a .harness/state/" "sed -i '' s/a/b/ $S" "sed -i.bak s/a/b/ $S" "sed -n -e 's/a/b/' -i $S" "perl -pi -e 's/a/b/' $S" \
    "python3 -c \"open('$S','w')\"" "python x.py $S" "python3.11 x.py $S" "node -e \"1\" $S" "ruby -e 1 $S" "perl -e 1 $S" "osascript -e 1 $S" \
    "env -u GITHUB_TOKEN rm $S" "/bin/rm $S" "cd $REPO && rm $S" "jq . $S && rm $S" "cat $S > /tmp/copy" \
    "echo x > $T" "rm $T" "mv $T /tmp/" "sed -i '' d $T" "python3 -c 'pass' $T" "echo x >> ~/.claude/projects/p/s.jsonl" "truncate -s 0 ~/.claude/projects/p/s.jsonl"; do
    bcheck deny "$c"
    [ "$(echo "$output" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "$REASON" ]
  done
}

@test "Bash: read-only uses of state and transcripts stay allowed" {
  export HARNESS_PROTECT_STATE=1
  S=".harness/state/s1.turn"
  T="$HOME/.claude/projects/-Users-x/abc.jsonl"
  for c in "cat $S" "jq . $S" "jq .spawned $REPO/$S" "tail -n 5 $T" "grep foo $S" "ls .harness/state" "wc -l $T" "head -c 100 $T" \
    "cat $S 2>/dev/null" "cat $S 2>&1 | head" "cat $S &>/dev/null" "jq . $T >/dev/null" "tail -f $T | jq ." "cat $S; ls" \
    "cat .harness/state/firmware.txt" "cat .harness/state/inode.txt" "cat .harness/state/ddrescue.log" "cat .harness/state/xpython" "git status" "cat ~/.claude/projects/p/s.jsonl"; do
    bcheck allow "$c"
  done
}

@test "Bash: writes that do not touch state or transcripts, including memory notes, stay allowed" {
  export HARNESS_PROTECT_STATE=1
  M="$HOME/.claude/projects/-Users-x/memory"
  for c in "rm -rf build" "echo x > out.txt" "sed -i '' s/a/b/ src/a.py" "python3 script.py" "node build.js" "mv a b" "cp a b" \
    "echo x > $M/MEMORY.md" "cp a $M/b.md" "rm $M/old.md" "cat ~/.claude/projects/p/notes.md > /tmp/x" "echo x > .harness/logs/x.log" \
    "python3 -c \"open('x','w')\""; do
    bcheck allow "$c"
  done
}

@test "works under the macOS system bash 3.2" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  export HARNESS_PROTECT_STATE=1
  run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(file_json Edit "$REPO/.harness/state/s1.turn")" "$HOOK"
  [ "$(decision)" = "deny" ]
  run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(bash_json 'rm .harness/state/s1.turn')" "$HOOK"
  [ "$(decision)" = "deny" ]
  run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(bash_json 'cat .harness/state/s1.turn')" "$HOOK"
  [ -z "$output" ]
}

@test "file tools: protected paths match case-insensitively (case-insensitive filesystems)" {
  export HARNESS_PROTECT_STATE=1
  for p in "$REPO/.Harness/State/x.turn" "$REPO/.HARNESS/STATE/x.turn" ".Harness/State/x.turn" "$REPO/.harness/STATE" \
    "$HOME/.Claude/Projects/-Users-x/ABC.JSONL" "$HOME/.claude/PROJECTS/-Users-x/abc.Jsonl" "$HOME/.CLAUDE/projects/-Users-x/Abc.jsonl"; do
    fcheck deny "$p"
  done
  TRANSCRIPT="$REPO/Elsewhere.txt"
  fcheck deny "$REPO/ELSEWHERE.TXT"
}

@test "file tools: mixed-case neighbours and memory notes stay writable" {
  export HARNESS_PROTECT_STATE=1
  for p in "$REPO/.HARNESS/LOGS/x.log" "$REPO/.Harness/State.txt" "$REPO/Src/State/a.kt" "$HOME/.Claude/Projects/-Users-x/Memory/MEMORY.md" \
    "$HOME/.claude/projects/-Users-x/memory/NOTE.MD" "$HOME/.Claude/Settings.json" "$REPO/Data.JSONL"; do
    fcheck allow "$p"
  done
}

@test "Bash: protected paths and write words match case-insensitively" {
  export HARNESS_PROTECT_STATE=1
  for c in 'echo 0 > .HARNESS/STATE/x.turn' 'rm .Harness/State/x.turn' 'RM .harness/state/x.turn' 'Echo x >> .Harness/state/x.turn' \
    'echo x > ~/.CLAUDE/PROJECTS/p/S.JSONL' "echo x > $HOME/.claude/Projects/p/S.Jsonl" 'rm ~/.Claude/projects/p/abc.JSONL' \
    "SED -i '' d .Harness/State/x.turn" 'Python3 -c 1 .HARNESS/state/x.turn' 'Touch ~/.claude/PROJECTS/p/s.jsonl'; do
    bcheck deny "$c"
  done
}

@test "Bash: mixed-case reads and unrelated or memory writes stay allowed" {
  export HARNESS_PROTECT_STATE=1
  for c in 'cat .HARNESS/STATE/x.turn' 'jq . .Harness/State/x.turn' "tail $HOME/.CLAUDE/projects/p/S.JSONL" 'CAT .harness/state/x.turn 2>/dev/null' \
    "echo x > $HOME/.Claude/Projects/p/Memory/MEMORY.md" 'rm -rf Build' 'echo x > OUT.TXT'; do
    bcheck allow "$c"
  done
}
