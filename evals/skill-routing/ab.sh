#!/bin/bash
# Router A/B: does the harness skill router make Claude invoke the right skill?
# Runs in a throwaway git repo with tools enabled, so skills are actually usable.
export _ZO_DOCTOR=0; S="$1"; : > "$S/ab2.out"
for rep in 1 2; do
  while IFS=$'\t' read -r exp p; do
    [ "$exp" = NONE ] && continue
    for arm in router norouter; do
      W=$(mktemp -d); (cd "$W" && git init -q && echo hi > README.md && git add -A && git -c user.email=e@e -c user.name=e commit -qm init)
      if [ $arm = norouter ]; then set -- --settings '{"env":{"HARNESS_SKILL_ROUTES":"/dev/null"}}'; else set --; fi
      out=$(cd "$W" && gtimeout 420 claude -p "$p" --max-turns 3 --strict-mcp-config --permission-mode bypassPermissions "$@" --output-format stream-json --verbose 2>/dev/null)
      tools=$(printf '%s' "$out" | jq -rR 'fromjson? | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name + (if .name=="Skill" then ":"+.input.skill else "" end)' | tr '\n' ',')
      hit=$(printf '%s' "$tools" | grep -c "Skill:$exp")
      printf '%s\t%s\t%s\t%s\n' "$arm" "$exp" "$hit" "${tools:-NOTOOLS}" >> "$S/ab2.out"
      rm -rf "$W"
    done
  done < "$S/held.tsv"
done
awk -F'\t' '{t[$1]++; h[$1]+=($3>0); nt[$1]+=($4=="NOTOOLS")} END{for(a in t) print a": right skill "h[a]"/"t[a]", sessions with no tools "nt[a]}' "$S/ab2.out"
