#!/usr/bin/env bash
# PreToolUse(Bash + mcp__*): opt-in guard rails for outbound actions (PR merges, blanket git add,
# shared stash, Slack and comment writes). Does nothing unless a knob is set.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

MERGE=0; HYGIENE=0; ASK=0
[ "${HARNESS_DENY_PR_MERGE:-}" = 1 ] && MERGE=1
[ "${HARNESS_GIT_HYGIENE:-}" = 1 ] && HYGIENE=1
[ "${HARNESS_ASK_OUTBOUND:-}" = 1 ] && ASK=1
[ "$MERGE$HYGIENE$ASK" != 000 ] || exit 0

hook_read_json
TOOL="$(hook_field '.tool_name // empty')"

MERGE_MSG='harness: merging is the human'"'"'s act. Say the PR is ready to merge; the user can run it with "! gh pr merge <n>".'
ASK_MSG='harness: Slack messages and comments need the human'"'"'s approval first.'
ADD_MSG='harness: stage explicit paths (git add path/a path/b) or use git add -u; never git add -A, --all or a bare ".", ":/" or "*".'
STASH_MSG='harness: this repo has several worktrees that share one stash stack. Use a WIP commit and "git reset --soft HEAD~1" instead of git stash.'

if [[ "$TOOL" == mcp__* ]]; then
  case "$TOOL" in
    *merge_pull_request)
      [ "$MERGE" = 1 ] && hook_decision deny "$MERGE_MSG" ;;
    *slack_send_message|*slack_schedule_message|*slack_create_canvas|*slack_update_canvas|*slack_add_reaction|*slack_create_conversation \
    |*addCommentToJiraIssue|*createConfluenceFooterComment|*createConfluenceInlineComment|*add_issue_comment|*create_pull_request_review)
      [ "$ASK" = 1 ] && hook_decision ask "$ASK_MSG" ;;
  esac
  exit 0
fi
[ "$TOOL" = Bash ] || exit 0

CMD="$(hook_field '.tool_input.command // empty')"
[ -n "$CMD" ] || exit 0
DIR="$(hook_field '.cwd // empty')"
DIR="${DIR:-$(hook_project_dir)}"

GH_RE="${HOOK_CMD_PREFIX}gh[[:space:]]+"
GIT_RE="${HOOK_CMD_PREFIX}git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?))*[[:space:]]+"
LEAD_RE='^[[:space:]]*(\{|!|if|then|else|elif|do|while|until)[[:space:]]+(.*)$'
MERGE_PATH_RE='pulls/[^/]+/merge($|[^[:alnum:]_-])'

# Words of a command tail, unglobbed and with one layer of surrounding quotes removed.
split_words() {
  local w i=0
  WORDS=()
  set -f
  for w in $1; do
    case "$w" in \"*|\'*) w="${w#?}" ;; esac
    case "$w" in *\"|*\') w="${w%?}" ;; esac
    WORDS[i]="$w"
    i=$((i + 1))
  done
  set +f
}

# 0 when `git add` stages blanket paths (-A, --all, a cluster with A, or a bare . :/ *).
blanket_add() {
  local i w endopts=0
  for ((i = 1; i < ${#WORDS[@]}; i++)); do
    w="${WORDS[i]}"
    if [ "$endopts" = 0 ]; then
      case "$w" in
        --) endopts=1; continue ;;
        --all) return 0 ;;
        --*) continue ;;
        -*A*) return 0 ;;
        -*) continue ;;
      esac
    fi
    case "$w" in .|./|:/|\*) return 0 ;; esac
  done
  return 1
}

# 0 when `gh api` writes (POST/PATCH/PUT, or fields without GET) to a comments/reviews/replies path.
comment_write() {
  local i w m="" path=0 fields=0
  for ((i = 1; i < ${#WORDS[@]}; i++)); do
    w="${WORDS[i]}"
    case "$w" in
      -X|--method) m="${WORDS[i+1]:-}" ;;
      --method=*) m="${w#--method=}" ;;
      -X?*) m="${w#-X}"; m="${m#=}" ;;
      -f|-F|-f?*|-F?*|--field|--field=*|--raw-field|--raw-field=*|--input|--input=*) fields=1 ;;
      */comments*|*/reviews*|*/replies*) path=1 ;;
    esac
  done
  [ "$path" = 1 ] || return 1
  m="$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')"
  case "$m" in POST|PATCH|PUT) return 0 ;; GET) return 1 ;; esac
  [ "$fields" = 1 ]
}

shared_stash() {
  case "${WORDS[1]:-}" in list|show) return 1 ;; esac
  [ "$(git -C "$(hook_cmd_dir "$CMD" "$DIR")" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')" -gt 1 ]
}

ASKED=0
while IFS= read -r SEG; do
  while [[ "$SEG" =~ $LEAD_RE ]]; do SEG="${BASH_REMATCH[2]}"; done
  if [[ "$SEG" =~ $GH_RE ]]; then
    REST="${SEG:${#BASH_REMATCH[0]}}"
    split_words "$REST"
    SUB="${WORDS[0]:-} ${WORDS[1]:-}"
    if [ "$MERGE" = 1 ]; then
      [ "$SUB" = "pr merge" ] && hook_decision deny "$MERGE_MSG"
      if [ "${WORDS[0]:-}" = api ]; then
        [[ "$REST" =~ $MERGE_PATH_RE || "$REST" == *mergePullRequest* || "$REST" == *enablePullRequestAutoMerge* ]] && hook_decision deny "$MERGE_MSG"
      fi
    fi
    if [ "$ASK" = 1 ]; then
      case "$SUB" in "pr comment"|"issue comment"|"pr review") ASKED=1 ;; esac
      if [ "${WORDS[0]:-}" = api ] && comment_write; then ASKED=1; fi
    fi
  elif [ "$HYGIENE" = 1 ] && [[ "$SEG" =~ $GIT_RE ]]; then
    REST="${SEG:${#BASH_REMATCH[0]}}"
    split_words "$REST"
    case "${WORDS[0]:-}" in
      add) blanket_add && hook_decision deny "$ADD_MSG" ;;
      stash) shared_stash && hook_decision deny "$STASH_MSG" ;;
    esac
  fi
done <<EOF2
$(printf '%s' "$CMD" | tr '\n;&|()`' '\n')
EOF2

[ "$ASKED" = 1 ] && hook_decision ask "$ASK_MSG"
exit 0
