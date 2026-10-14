#!/usr/bin/env bats

load helpers

setup() {
  unset HARNESS_DENY_PR_MERGE HARNESS_GIT_HYGIENE HARNESS_ASK_OUTBOUND
  HOOK="$SCRIPTS/pre-outbound-gate.sh"
  new_repo
}

teardown() {
  rm -rf "$REPO" "${WT:+$(dirname "$WT")}" "${FAKE:-}"
}

bash_json() { jq -nc --arg c "$1" --arg cwd "${2:-$REPO}" '{session_id: "s1", tool_name: "Bash", cwd: $cwd, tool_input: {command: $c}}'; }
mcp_json() { jq -nc --arg t "$1" --arg cwd "$REPO" '{session_id: "s1", tool_name: $t, cwd: $cwd, tool_input: {}}'; }
decision() { if [ -z "$output" ]; then echo allow; else echo "$output" | jq -r '.hookSpecificOutput.permissionDecision'; fi; }
reason() { echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }

# check <allow|deny|ask> <command> [cwd]
check() {
  run_hook "$HOOK" "$(bash_json "$2" "${3:-$REPO}")"
  [ "$status" -eq 0 ] || { echo "status $status for: $2 -> $output"; return 1; }
  [ "$(decision)" = "$1" ] || { echo "expected $1, got $(decision) for: $2"; return 1; }
  if [ "$1" = allow ]; then [ -z "$output" ] || { echo "output on allow for: $2 -> $output"; return 1; }; fi
}

# mcheck <allow|deny|ask> <tool name>
mcheck() {
  run_hook "$HOOK" "$(mcp_json "$2")"
  [ "$status" -eq 0 ] || { echo "status $status for: $2 -> $output"; return 1; }
  [ "$(decision)" = "$1" ] || { echo "expected $1, got $(decision) for: $2"; return 1; }
}

two_worktrees() {
  git_commit -m init
  WT="$(mktemp -d)/wt"
  git -C "$REPO" worktree add -q "$WT" -b wt
}

MERGE_REASON='harness: merging is the human'"'"'s act. Say the PR is ready to merge; the user can run it with "! gh pr merge <n>".'
ASK_REASON='harness: Slack messages and comments need the human'"'"'s approval first.'

@test "with no knob set every call passes untouched, even malformed input" {
  check allow 'gh pr merge 12'
  check allow 'git add -A'
  check allow 'git stash'
  check allow 'gh pr comment 3 -b hi'
  mcheck allow mcp__claude_ai_Slack__slack_send_message
  mcheck allow mcp__plugin_yuno_github__merge_pull_request
  run_hook "$HOOK" 'not json'
  [ "$status" -eq 0 ] && [ -z "$output" ]
  export HARNESS_DENY_PR_MERGE=0 HARNESS_GIT_HYGIENE="" HARNESS_ASK_OUTBOUND=no
  check allow 'gh pr merge 12'
  mcheck allow mcp__claude_ai_Slack__slack_send_message
}

@test "with no knob set the gate does not even need jq; with one set it does" {
  FAKE="$(tool_path jq)"
  run_hook_with_path "$FAKE" "$HOOK" "$(bash_json 'gh pr merge 1')"
  [ "$status" -eq 0 ]
  run env -i HOME="$HOME" PATH="$FAKE" HARNESS_GIT_HYGIENE=1 bash -c 'printf "%s" "$1" | bash "$2"' _ "$(bash_json 'git add .')" "$HOOK"
  [ "$status" -eq 2 ]
}

@test "with a knob set, unparseable input fails closed and other tools pass" {
  export HARNESS_DENY_PR_MERGE=1 HARNESS_GIT_HYGIENE=1 HARNESS_ASK_OUTBOUND=1
  run_hook "$HOOK" 'not json'
  [ "$status" -eq 2 ]
  run_hook "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
  [ "$status" -eq 0 ] && [ -z "$output" ]
  mcheck allow mcp__claude_ai_Slack__slack_read_channel
}

@test "HARNESS_DENY_PR_MERGE denies gh pr merge in every prefix form, with the exact reason" {
  export HARNESS_DENY_PR_MERGE=1
  for c in 'gh pr merge 12' 'gh pr merge 12 --squash --delete-branch' 'env -u GITHUB_TOKEN gh pr merge 12' \
    'GH_REPO=o/r gh pr merge 12' 'env -i FOO=bar gh pr merge 12' 'cd /tmp && gh pr merge 12' \
    'echo hi; gh pr merge 12 --auto' 'true && env -u GITHUB_TOKEN gh pr merge' '(gh pr merge 3)'; do
    check deny "$c"
    [ "$(reason)" = "$MERGE_REASON" ]
  done
}

@test "HARNESS_DENY_PR_MERGE denies the merge endpoint and the merge mutations of gh api" {
  export HARNESS_DENY_PR_MERGE=1
  check deny 'gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=squash'
  check deny 'env -u GITHUB_TOKEN gh api repos/{owner}/{repo}/pulls/12/merge --method PUT'
  check deny "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }'"
  check deny "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {pullRequestId: \"x\"}) { clientMutationId } }'"
}

@test "HARNESS_DENY_PR_MERGE denies any MCP merge_pull_request tool" {
  export HARNESS_DENY_PR_MERGE=1
  mcheck deny mcp__plugin_yuno_github__merge_pull_request
  mcheck deny mcp__github__merge_pull_request
  [ "$(reason)" = "$MERGE_REASON" ]
  mcheck allow mcp__plugin_yuno_github__create_pull_request
  mcheck allow mcp__plugin_yuno_github__get_pull_request
}

@test "HARNESS_DENY_PR_MERGE leaves everything else alone" {
  export HARNESS_DENY_PR_MERGE=1
  for c in 'gh pr view 12' 'gh pr list' 'gh pr create --title x' 'gh pr checks 12' 'gh pr comment 12 -b x' \
    'echo "gh pr merge 12"' 'gh api repos/o/r/pulls/12' 'gh api repos/o/r/pulls/12/comments' 'git merge main' 'git log --merges' \
    'git add .' 'ls -la'; do
    check allow "$c"
  done
}

@test "merge is only denied when its own knob is set" {
  export HARNESS_GIT_HYGIENE=1
  check allow 'gh pr merge 12'
  mcheck allow mcp__plugin_yuno_github__merge_pull_request
}

@test "HARNESS_GIT_HYGIENE denies blanket staging: -A, --all, clusters with A, and . :/ * paths" {
  export HARNESS_GIT_HYGIENE=1
  for c in 'git add -A' 'git add --all' 'git add -vA' 'git add -Av' 'git add -f -A' 'git add .' 'git add -- .' 'git add :/' 'git add *' \
    'git add ./' 'git add "."' "git add '.'" 'git add a.txt .' 'env -u GITHUB_TOKEN git add .' 'FOO=bar git add -A' \
    "git -C $REPO add ." 'cd /tmp && git add .' 'git add a.txt && git add .' 'git add a.txt; git add -A && git commit -m x' \
    'true || git add --all'; do
    check deny "$c"
    case "$(reason)" in *"git add -u"*"explicit paths"*|*"explicit paths"*"git add -u"*) ;; *) echo "reason: $(reason)"; false ;; esac
  done
}

@test "HARNESS_GIT_HYGIENE allows explicit paths, -u and look-alikes" {
  export HARNESS_GIT_HYGIENE=1
  for c in 'git add ./src/a.kt' 'git add -u' 'git add --update' 'git add path/a path/b' 'git add -- path/a' 'git add src/*.kt' \
    'git add -p path/a' 'git add -N new.txt' 'git add .gitignore' 'git add a..b' 'git add' 'git status' 'git commit -m "add ."' \
    'echo "git add ."' 'env -u GITHUB_TOKEN git add src/a.kt' 'git addendum .' 'git diff -A'; do
    check allow "$c"
  done
}

@test "a literal * path is not expanded against the hook's cwd" {
  export HARNESS_GIT_HYGIENE=1
  touch "$REPO/a.txt" "$REPO/b.txt"
  cd "$REPO"
  check deny 'git add *'
}

@test "HARNESS_GIT_HYGIENE allows git stash in a single-worktree repo" {
  export HARNESS_GIT_HYGIENE=1
  git_commit -m init
  for c in 'git stash' 'git stash push -m x' 'git stash pop' 'git stash list'; do
    check allow "$c"
  done
}

@test "HARNESS_GIT_HYGIENE denies every git stash except list and show when worktrees are shared" {
  export HARNESS_GIT_HYGIENE=1
  two_worktrees
  for c in 'git stash' 'git stash push -m x' 'git stash pop' 'git stash apply' 'git stash drop' 'git stash clear' 'git stash save x' \
    'git stash -u' 'git stash branch b' 'env -u GITHUB_TOKEN git stash' 'cd /tmp && git -C . stash'; do
    check deny "$c"
    case "$(reason)" in *"worktree"*"WIP commit"*"git reset --soft HEAD~1"*) ;; *) echo "reason: $(reason)"; false ;; esac
  done
  for c in 'git stash list' 'git stash show' 'git stash show -p stash@{0}' 'git stash list --oneline' 'git status'; do
    check allow "$c"
  done
}

@test "git stash follows -C and cd to the target repo, and works from the linked worktree" {
  export HARNESS_GIT_HYGIENE=1
  two_worktrees
  OTHER="$(mktemp -d)"
  check deny "git -C $REPO stash" "$OTHER"
  check deny "cd $REPO && git stash" "$OTHER"
  check deny 'git stash' "$WT"
  rm -rf "$OTHER"
}

@test "HARNESS_ASK_OUTBOUND asks for the Slack write tools but not the draft or the readers" {
  export HARNESS_ASK_OUTBOUND=1
  for t in slack_send_message slack_schedule_message slack_create_canvas slack_update_canvas slack_add_reaction slack_create_conversation; do
    mcheck ask "mcp__claude_ai_Slack__$t"
    [ "$(reason)" = "$ASK_REASON" ]
  done
  mcheck ask mcp__plugin_engineering_slack__slack_send_message
  mcheck allow mcp__claude_ai_Slack__slack_send_message_draft
  for t in slack_read_channel slack_read_thread slack_search_public slack_search_users slack_get_reactions slack_read_canvas; do
    mcheck allow "mcp__claude_ai_Slack__$t"
  done
}

@test "HARNESS_ASK_OUTBOUND asks for Jira, Confluence and GitHub comment tools" {
  export HARNESS_ASK_OUTBOUND=1
  for t in mcp__claude_ai_Atlassian_Rovo__addCommentToJiraIssue mcp__claude_ai_Atlassian_Rovo__createConfluenceFooterComment \
    mcp__claude_ai_Atlassian_Rovo__createConfluenceInlineComment mcp__plugin_yuno_github__add_issue_comment \
    mcp__plugin_yuno_github__create_pull_request_review; do
    mcheck ask "$t"
    [ "$(reason)" = "$ASK_REASON" ]
  done
  for t in mcp__claude_ai_Atlassian_Rovo__getJiraIssue mcp__claude_ai_Atlassian_Rovo__editJiraIssue mcp__claude_ai_Atlassian_Rovo__getConfluencePageFooterComments \
    mcp__plugin_yuno_github__get_pull_request_comments mcp__plugin_yuno_github__create_pull_request mcp__plugin_yuno_github__get_pull_request_reviews; do
    mcheck allow "$t"
  done
}

@test "HARNESS_ASK_OUTBOUND asks for gh comment and review commands in every prefix form" {
  export HARNESS_ASK_OUTBOUND=1
  for c in 'gh pr comment 12 -b x' 'gh issue comment 5 --body-file f.md' 'gh pr review 12 --approve' 'env -u GITHUB_TOKEN gh pr comment 12 -b x' \
    'GH_REPO=o/r gh issue comment 5 -b x' 'cd /tmp && gh pr review 3 -c -b x' 'git push && gh pr comment 1 -b done'; do
    check ask "$c"
    [ "$(reason)" = "$ASK_REASON" ]
  done
}

@test "HARNESS_ASK_OUTBOUND asks for gh api writes to comments, reviews and replies" {
  export HARNESS_ASK_OUTBOUND=1
  for c in 'gh api repos/o/r/issues/5/comments -f body=x' 'gh api repos/o/r/pulls/5/comments -X POST -f body=x' \
    'gh api -X PATCH repos/o/r/issues/comments/9 -f body=x' 'gh api --method PUT repos/o/r/pulls/5/comments/1' \
    'gh api --method=POST repos/o/r/issues/5/comments' 'gh api -XPOST repos/o/r/issues/5/comments' \
    'gh api repos/o/r/pulls/5/reviews --input review.json' 'gh api repos/o/r/pulls/5/comments/7/replies -f body=x' \
    'gh api repos/o/r/issues/5/comments -F body=@msg.md' 'gh api repos/o/r/issues/5/comments --field body=x' \
    'gh api repos/o/r/issues/5/comments --raw-field body=x' 'gh api repos/{owner}/{repo}/pulls/5/reviews -X POST' \
    'env -u GITHUB_TOKEN gh api repos/o/r/issues/5/comments -f body=x' 'gh api -X POST repos/o/r/issues/5/comments'; do
    check ask "$c"
    [ "$(reason)" = "$ASK_REASON" ]
  done
}

@test "HARNESS_ASK_OUTBOUND lets read-only gh api and other gh commands through" {
  export HARNESS_ASK_OUTBOUND=1
  for c in 'gh api repos/o/r/issues/5/comments' 'gh api repos/o/r/pulls/5/comments --paginate' 'gh api repos/o/r/issues/5/comments -X GET' \
    'gh api -X GET repos/o/r/issues/5/comments -f per_page=100' 'gh api repos/o/r/pulls/5/reviews --jq ".[].state"' \
    'gh api -X POST repos/o/r/issues -f title=x' 'gh api repos/o/r/pulls/5' 'gh pr view 12 --comments' 'gh pr list' 'gh issue list' \
    'gh pr checks 12' 'gh pr create --title x' 'gh pr merge 12' 'echo "gh pr comment 1"' 'git add .'; do
    check allow "$c"
  done
}

@test "a deny wins over an ask in the same command" {
  export HARNESS_DENY_PR_MERGE=1 HARNESS_ASK_OUTBOUND=1
  check deny 'gh pr comment 1 -b done && gh pr merge 1'
  check deny 'gh pr merge 1; gh pr comment 1 -b done'
  check ask 'gh pr comment 1 -b done && gh pr view 1'
}

@test "the three knobs work together and independently" {
  export HARNESS_DENY_PR_MERGE=1 HARNESS_GIT_HYGIENE=1 HARNESS_ASK_OUTBOUND=1
  check deny 'gh pr merge 1'
  check deny 'git add -A'
  check ask 'gh pr comment 1 -b x'
  check allow 'git add src/a.kt'
  mcheck deny mcp__plugin_yuno_github__merge_pull_request
  mcheck ask mcp__claude_ai_Slack__slack_send_message
}

@test "emits the same JSON shape as the delegation gate" {
  export HARNESS_DENY_PR_MERGE=1 HARNESS_ASK_OUTBOUND=1
  run_hook "$HOOK" "$(bash_json 'gh pr merge 12')"
  [ "$(echo "$output" | jq -c .)" = "$(jq -nc --arg r "$MERGE_REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}')" ]
  run_hook "$HOOK" "$(bash_json 'gh pr comment 12 -b x')"
  [ "$(echo "$output" | jq -c .)" = "$(jq -nc --arg r "$ASK_REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}')" ]
}

@test "works under the macOS system bash 3.2" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  export HARNESS_DENY_PR_MERGE=1 HARNESS_GIT_HYGIENE=1 HARNESS_ASK_OUTBOUND=1
  for case_ in "gh pr merge 1:deny" "env -u GITHUB_TOKEN git add .:deny" "gh pr comment 1 -b x:ask" "git add a.txt:allow"; do
    run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(bash_json "${case_%:*}")" "$HOOK"
    [ "$status" -eq 0 ]
    [ "$(decision)" = "${case_##*:}" ]
  done
}

@test "wrappers: bash -c, sh -c, zsh -c and eval are scanned on their inner command" {
  export HARNESS_DENY_PR_MERGE=1 HARNESS_GIT_HYGIENE=1 HARNESS_ASK_OUTBOUND=1
  for c in 'bash -c "gh pr merge 12"' "sh -c 'gh pr merge 12'" 'zsh -c "gh pr merge 12"' 'bash -lc "gh pr merge 12"' 'bash -c gh pr merge 12' \
    '/bin/bash -c "gh pr merge 12"' 'env -u GITHUB_TOKEN bash -c "env -u GITHUB_TOKEN gh pr merge 12"' "bash -c \"bash -c 'gh pr merge 12'\"" \
    'eval "gh pr merge 12"' 'cd /tmp && sudo bash -c "gh pr merge 1"' 'bash -x -c "gh pr merge 1"' 'bash -c "echo hi; gh pr merge 1"' \
    'bash -c "git add -A"' "sh -c 'git add .'" 'zsh -c "cd /tmp && git add --all"' 'FOO=1 bash -c "git add -- ."'; do
    check deny "$c"
  done
  check ask 'bash -c "gh pr comment 1 -b x"'
  check ask "sh -c 'gh api repos/o/r/issues/5/comments -f body=x'"
}

@test "wrappers: nested wrappers with escaped inner quotes are unwrapped too" {
  export HARNESS_DENY_PR_MERGE=1 HARNESS_GIT_HYGIENE=1
  check deny 'bash -c "bash -c \"gh pr merge 12\""'
  check deny 'sh -c "zsh -c \"git add -A\""'
  check deny "bash -c \"eval 'gh pr merge 12'\""
}

@test "wrappers: harmless inner commands and non-wrapper bash/sh uses stay allowed" {
  export HARNESS_DENY_PR_MERGE=1 HARNESS_GIT_HYGIENE=1 HARNESS_ASK_OUTBOUND=1
  for c in 'bash -c "git status"' 'bash -c "gh pr view 12"' "sh -c 'echo hi'" 'bash script.sh' 'bash -c "git add src/a.kt"' 'zsh -c "ls -la"' \
    'eval "ls"' 'bash -c ""' 'bash -c "gh api repos/o/r/issues/5/comments"' 'bash -n script.sh' 'bash --version' 'bash gh-pr-merge.sh'; do
    check allow "$c"
  done
}

@test "wrappers: git stash inside bash -c sees the shared stash" {
  export HARNESS_GIT_HYGIENE=1
  two_worktrees
  check deny 'bash -c "git stash"'
  check deny "sh -c 'git stash push -m x'"
  check allow 'bash -c "git stash list"'
}

@test "merge via the raw GitHub API is denied for curl, wget and httpie, and for GraphQL bodies" {
  export HARNESS_DENY_PR_MERGE=1
  for c in "curl -X PUT https://api.github.com/repos/o/r/pulls/12/merge -d '{\"merge_method\":\"squash\"}'" \
    'curl -s -X PUT -H "Authorization: Bearer ghp_x" "https://api.github.com/repos/o/r/pulls/12/merge"' \
    'curl https://api.github.com/repos/o/r/pulls/12/merge' 'curl -X PUT "https://api.github.com/repos/o/r/pulls/$N/merge"' \
    'wget --method=PUT https://api.github.com/repos/o/r/pulls/12/merge' 'http PUT api.github.com/repos/o/r/pulls/12/merge' \
    'https PUT https://api.github.com/repos/o/r/pulls/12/merge' 'env -u GITHUB_TOKEN curl -X PUT https://api.github.com/repos/o/r/pulls/12/merge' \
    'bash -c "curl -X PUT https://api.github.com/repos/o/r/pulls/12/merge"' 'gh api repos/o/r/pulls/12/merge -X PUT' \
    "curl -X POST https://api.github.com/graphql -d '{\"query\":\"mutation { mergePullRequest(input: {pullRequestId: \\\"x\\\"}) { clientMutationId } }\"}'" \
    "curl -X POST https://api.github.com/graphql -d '{\"query\":\"mutation { enablePullRequestAutoMerge(input: {pullRequestId: \\\"x\\\"}) { clientMutationId } }\"}'" \
    "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {pullRequestId: \"x\"}) { clientMutationId } }'"; do
    check deny "$c"
    [ "$(reason)" = "$MERGE_REASON" ]
  done
}

@test "merge via the raw GitHub API: reads and look-alikes stay allowed, and the knob gates it" {
  export HARNESS_DENY_PR_MERGE=1
  for c in 'curl https://api.github.com/repos/o/r/pulls/12' 'curl https://api.github.com/repos/o/r/pulls/12/files' \
    'curl https://api.github.com/repos/o/r/pulls/12/comments' 'curl https://example.com/repos/o/r/pulls/12/merge' \
    'git commit -m "docs: mergePullRequest and enablePullRequestAutoMerge"' 'echo mergePullRequest' 'grep -rn mergePullRequest src/' \
    "gh api graphql -f query='{ viewer { login } }'" "curl https://api.github.com/graphql -d '{\"query\":\"{ viewer { login } }\"}'"; do
    check allow "$c"
  done
  unset HARNESS_DENY_PR_MERGE
  export HARNESS_GIT_HYGIENE=1
  check allow 'curl -X PUT https://api.github.com/repos/o/r/pulls/12/merge'
}

@test "ask: curl, wget and httpie writes to GitHub comments, reviews and replies" {
  export HARNESS_ASK_OUTBOUND=1
  B='{"body":"x"}'
  for c in "curl -X POST -d '$B' https://api.github.com/repos/o/r/issues/5/comments" \
    "curl --request PATCH -d '$B' https://api.github.com/repos/o/r/issues/comments/9" \
    "curl -d '$B' https://api.github.com/repos/o/r/issues/5/comments" \
    'curl --data-binary @f.json https://api.github.com/repos/o/r/pulls/5/reviews' \
    "curl --data-raw '$B' https://api.github.com/repos/o/r/issues/5/comments" \
    "curl --json '$B' https://api.github.com/repos/o/r/issues/5/comments" \
    'curl -F body=x https://api.github.com/repos/o/r/pulls/5/comments/7/replies' \
    'curl --form body=x https://api.github.com/repos/o/r/issues/5/comments' \
    'curl -XPOST https://api.github.com/repos/o/r/issues/5/comments' \
    'curl -H "Accept: application/vnd.github+json" -X POST https://api.github.com/repos/o/r/pulls/5/reviews' \
    "curl -X POST -d '{\"body\":\"ok (see above); thanks & bye | done\"}' https://api.github.com/repos/o/r/issues/5/comments" \
    'curl -X POST "https://api.github.com/repos/o/r/issues/5/comments?x=1" -d @-' \
    "wget --method=POST --body-data='$B' https://api.github.com/repos/o/r/issues/5/comments" \
    "wget --post-data='$B' https://api.github.com/repos/o/r/issues/5/comments" \
    'http POST api.github.com/repos/o/r/issues/5/comments body=x' 'http --json POST https://api.github.com/repos/o/r/issues/5/comments body=hi' \
    'http api.github.com/repos/o/r/issues/5/comments body=hi' 'https PATCH api.github.com/repos/o/r/issues/comments/9 body=hi' \
    'env -u GITHUB_TOKEN curl -X POST -d x https://api.github.com/repos/o/r/issues/5/comments' \
    'bash -c "curl -X POST -d x https://api.github.com/repos/o/r/issues/5/comments"'; do
    check ask "$c"
    [ "$(reason)" = "$ASK_REASON" ]
  done
}

@test "ask: reading GitHub comments with curl, wget or httpie stays allowed" {
  export HARNESS_ASK_OUTBOUND=1
  for c in 'curl https://api.github.com/repos/o/r/pulls/1/comments' 'curl -s -H "Authorization: Bearer ghp_x" https://api.github.com/repos/o/r/issues/5/comments' \
    'curl -X GET -d per_page=100 https://api.github.com/repos/o/r/issues/5/comments' 'curl -G -d per_page=100 https://api.github.com/repos/o/r/issues/5/comments' \
    'curl -o out.json https://api.github.com/repos/o/r/issues/5/comments' 'curl -X POST -d x https://api.github.com/repos/o/r/issues' \
    'curl -X POST -d x https://example.com/comments' 'http api.github.com/repos/o/r/issues/5/comments' \
    'http GET api.github.com/repos/o/r/issues/5/comments page==2' 'wget -qO- https://api.github.com/repos/o/r/issues/5/comments' \
    'curl -X DELETE https://api.github.com/repos/o/r/issues/comments/9' "curl -d '{\"query\":\"{ viewer { login } }\"}' https://api.github.com/graphql"; do
    check allow "$c"
  done
}

@test "ask: GraphQL mutations that post comments or reviews, via gh api graphql or curl" {
  export HARNESS_ASK_OUTBOUND=1
  for m in addComment addPullRequestReview addPullRequestReviewComment addPullRequestReviewThreadReply addDiscussionComment; do
    check ask "gh api graphql -f query='mutation { $m(input: {subjectId: \"x\", body: \"y\"}) { clientMutationId } }'"
    check ask "curl -X POST https://api.github.com/graphql -d '{\"query\":\"mutation { $m(input: {}) { clientMutationId } }\"}'"
  done
  [ "$(reason)" = "$ASK_REASON" ]
  for c in "gh api graphql -f query='{ viewer { login } }'" \
    "gh api graphql -f query='{ repository(owner:\"o\", name:\"r\") { pullRequest(number:1) { reviews(first:5) { nodes { state } } } } }'" \
    'git commit -m "docs: addComment helper"' 'grep -rn addComment src/'; do
    check allow "$c"
  done
}

@test "ask: Slack web API writes and incoming webhooks" {
  export HARNESS_ASK_OUTBOUND=1
  for m in chat.postMessage chat.scheduleMessage chat.update reactions.add conversations.create canvases.create canvases.edit; do
    check ask "curl -X POST -H 'Authorization: Bearer xoxb-x' -d channel=C1 https://slack.com/api/$m"
  done
  check ask "curl -X POST -d '{\"text\":\"x\"}' https://hooks.slack.com/services/T000/B000/XXX"
  check ask "python3 -c \"import requests; requests.post('https://slack.com/api/chat.postMessage', json={})\""
  check ask 'curl -d text=hi https://myco.slack.com/api/chat.postMessage'
  [ "$(reason)" = "$ASK_REASON" ]
  for c in 'curl https://slack.com/api/conversations.history -d channel=C1' 'curl https://slack.com/api/auth.test' 'curl https://slack.com/api/users.list' \
    'curl https://slack.com/api/chat.getPermalink -d channel=C1' 'curl https://slack.com/api/conversations.list' 'echo hi'; do
    check allow "$c"
  done
}

@test "ask: Atlassian REST comment writes" {
  export HARNESS_ASK_OUTBOUND=1
  for c in "curl -u a:b -X POST -H 'Content-Type: application/json' https://y.atlassian.net/rest/api/3/issue/ABC-1/comment -d '{\"body\":\"x\"}'" \
    'curl -X PUT -d x https://y.atlassian.net/rest/api/3/issue/ABC-1/comment/10' 'curl -d @c.json https://y.atlassian.net/rest/api/content/123/child/comment' \
    "curl --json '{}' https://y.atlassian.net/rest/api/2/issue/ABC-1/comment" 'http POST y.atlassian.net/rest/api/3/issue/ABC-1/comment body=x' \
    'wget --post-data=x https://y.atlassian.net/rest/api/3/issue/ABC-1/comment'; do
    check ask "$c"
  done
  [ "$(reason)" = "$ASK_REASON" ]
  for c in 'curl -u a:b https://y.atlassian.net/rest/api/3/issue/ABC-1/comment' 'curl -u a:b https://y.atlassian.net/rest/api/3/issue/ABC-1' \
    'curl -X POST -d x https://y.atlassian.net/rest/api/3/issue' 'curl -X GET https://y.atlassian.net/rest/api/3/issue/ABC-1/comment' \
    'curl -X POST -d x https://y.atlassian.net/rest/api/3/search'; do
    check allow "$c"
  done
}

@test "the new ask rules are off without HARNESS_ASK_OUTBOUND, and a deny still wins" {
  export HARNESS_DENY_PR_MERGE=1
  check allow 'curl -X POST -d x https://api.github.com/repos/o/r/issues/5/comments'
  check allow 'curl -X POST -d text=hi https://slack.com/api/chat.postMessage'
  check allow 'curl -X POST -d x https://y.atlassian.net/rest/api/3/issue/ABC-1/comment'
  check allow "gh api graphql -f query='mutation { addComment(input: {}) { clientMutationId } }'"
  check allow 'bash -c "gh pr comment 1 -b x"'
  export HARNESS_ASK_OUTBOUND=1
  check deny 'curl -X POST -d x https://api.github.com/repos/o/r/issues/1/comments && curl -X PUT https://api.github.com/repos/o/r/pulls/1/merge'
  check deny 'bash -c "curl -X POST -d x https://slack.com/api/chat.postMessage; gh pr merge 1"'
}

@test "git stash fails closed when the worktree list cannot be read, but list and show still pass" {
  export HARNESS_GIT_HYGIENE=1
  OTHER="$(mktemp -d)"
  for c in 'git stash' 'git stash push -m x' 'git stash pop' 'git stash -u'; do
    check deny "$c" "$OTHER"
    case "$(reason)" in *"worktree"*"WIP commit"*"git reset --soft HEAD~1"*) ;; *) echo "reason: $(reason)"; false ;; esac
  done
  check allow 'git stash list' "$OTHER"
  check allow 'git stash show -p' "$OTHER"
  rm -rf "$OTHER"
}

@test "git stash fails closed when git errors out or lists no worktrees" {
  export HARNESS_GIT_HYGIENE=1
  git_commit -m init
  FAKE="$(mktemp -d)"
  printf '#!/bin/sh\nexit 1\n' > "$FAKE/git"
  printf '#!/bin/sh\nexit 0\n' > "$FAKE/git-silent"
  chmod +x "$FAKE/git" "$FAKE/git-silent"
  PATH="$FAKE:$PATH" check deny 'git stash'
  cp "$FAKE/git-silent" "$FAKE/git"
  PATH="$FAKE:$PATH" check deny 'git stash push'
  PATH="$FAKE:$PATH" check allow 'git stash list'
  PATH="$FAKE:$PATH" check allow 'git status'
}

@test "git stash is still allowed in single-worktree repos: fresh, with commits, from a subdirectory" {
  export HARNESS_GIT_HYGIENE=1
  check allow 'git stash'
  git_commit -m init
  mkdir "$REPO/sub"
  check allow 'git stash'
  check allow 'git stash push -m x' "$REPO/sub"
  check allow "git -C $REPO stash pop" "$(mktemp -d)"
}
