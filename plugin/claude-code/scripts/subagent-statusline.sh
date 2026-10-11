#!/usr/bin/env bash
# subagentStatusLine: prefix each subagent row with its model. Never fails loudly:
# bad input prints nothing and exits 0; tasks without a model keep the default row.
command -v jq >/dev/null 2>&1 || exit 0
jq -c '
  (.columns // 80) as $cols
  | .tasks[]?
  | select((.model // "") != "")
  | { id, content: (
      ([ (.model | sub("^claude-"; "")),
         (.agentType // .type // empty),
         (.label // .description // empty),
         (.effort // empty) ] | map(select(. != "")) | join(" · "))
      | .[0:$cols] ) }
' 2>/dev/null || true
exit 0
