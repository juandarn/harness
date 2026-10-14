#!/usr/bin/env bash
# PreToolUse(Bash + file tools): with HARNESS_PROTECT_STATE=1, denies writes to .harness/state and
# to session transcripts (the hooks' own evidence). No agent_id exemption.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

[ "${HARNESS_PROTECT_STATE:-}" = 1 ] || exit 0

hook_read_json
TOOL="$(hook_field '.tool_name // empty')"
MSG="harness: .harness/state and session transcripts are the hooks' evidence; they are written only by the hooks. Leave them alone."
CWD="$(hook_field '.cwd // empty')"
CWD="${CWD:-$(hook_project_dir)}"
LIVE="$(hook_field '.transcript_path // empty')"
REAL_HOME="$(cd "$HOME" 2>/dev/null && pwd -P)"

# macOS filesystems are case-insensitive: every path and command comparison is done lowercased.
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
HOME_L="$(lower "$HOME")"
REAL_HOME_L="$(lower "$REAL_HOME")"
LIVE_L="$(lower "$LIVE")"

# Lexical normalization of an absolute path: drops empty and . parts, applies ..
normalize() {
  local IFS=/ part out=""
  set -f
  for part in $1; do
    case "$part" in
      ''|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$part" ;;
    esac
  done
  set +f
  printf '%s' "${out:-/}"
}

protected() {
  local p
  p="$(lower "$1")"
  case "$p/" in */.harness/state/*) return 0 ;; esac
  case "$p" in "$HOME_L"/.claude/projects/*.jsonl|"$REAL_HOME_L"/.claude/projects/*.jsonl) return 0 ;; esac
  [ -n "$LIVE_L" ] && [ "$p" = "$LIVE_L" ]
}

# 0 when the target, spelled lexically, through symlinked directories or as a symlink, is protected.
protected_target() {
  local raw="$1" dir real q hops=0 t
  case "$raw" in /*) ;; *) raw="$CWD/$raw" ;; esac
  protected "$(normalize "$raw")" && return 0
  dir="$(hook_existing_dir "$raw")"
  real="$(cd "$dir" 2>/dev/null && pwd -P)"
  q="$(normalize "${real:-$dir}${raw#"$dir"}")"
  protected "$q" && return 0
  while [ -L "$q" ] && [ "$hops" -lt 10 ]; do
    t="$(readlink "$q")"
    case "$t" in /*) ;; *) t="$(dirname -- "$q")/$t" ;; esac
    q="$(normalize "$t")"
    protected "$q" && return 0
    hops=$((hops + 1))
  done
  return 1
}

case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit)
    TARGET="$(hook_field '.tool_input.file_path // .tool_input.notebook_path // empty')"
    [ -n "$TARGET" ] || hook_decision deny "harness: state guard could not read the target path — denying instead of guessing."
    protected_target "$TARGET" && hook_decision deny "$MSG"
    exit 0 ;;
  Bash) ;;
  *) exit 0 ;;
esac

CMD="$(lower "$(hook_field '.tool_input.command // empty')")"
if [[ "$CMD" != *.harness/state* ]] && ! [[ "$CMD" == *.claude/projects/* && "$CMD" == *.jsonl* ]]; then exit 0; fi

# Redirections to /dev/null and fd duplications (2>&1) cannot write to a protected file.
SANS="$(printf '%s' "$CMD" | sed -E 's/[0-9]*>&[0-9-]+//g; s|&?[0-9]*>>?[[:space:]]*/dev/null||g')"
WORD_RE='(^|[^[:alnum:]_./-]|/s?bin/)(rm|mv|cp|tee|touch|truncate|dd|ln|install|chmod|rsync|python[0-9.]*|node|ruby|perl|osascript)([^[:alnum:]_.-]|$)'
SED_RE='(^|[^[:alnum:]_./-]|/s?bin/)sed[[:space:]]+([^;&|]*[[:space:]])?(-[A-Za-z]*i|--in-place)'
if [[ "$SANS" == *">"* || "$SANS" =~ $WORD_RE || "$SANS" =~ $SED_RE ]]; then
  hook_decision deny "$MSG"
fi
exit 0
