#!/usr/bin/env bash
# Verifies every tool the manifest pins is present. Reports missing tools; a
# missing tool must be surfaced here, never discovered as a silently-skipped gate.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gates/lib.sh"

only="${1:-all}"

awk '
  /^adapters:/ {section="a"; next}
  /^thresholds:/ {section=""}
  section=="a" && /^  [a-z]+:$/ {gsub(/[: ]/,""); adapter=$0; next}
  section=="a" && /^    [a-z]/ {gsub(/:/,""); print adapter, $1}
' "$(manifest)" | while read -r adapter tool; do
  [ "$only" != "all" ] && [ "$only" != "$adapter" ] && continue
  if command -v "$tool" >/dev/null 2>&1; then
    grn "  ok    $adapter/$tool"
  else
    red "  MISS  $adapter/$tool"
  fi
done

# subshell above can't mutate $missing; recompute exit status directly
if awk '
  /^adapters:/ {s="a"; next} /^thresholds:/ {s=""}
  s=="a" && /^  [a-z]+:$/ {gsub(/[: ]/,"");a=$0;next}
  s=="a" && /^    [a-z]/ {gsub(/:/,"");print a,$1}
' "$(manifest)" | while read -r a t; do
  [ "$only" != "all" ] && [ "$only" != "$a" ] && continue
  command -v "$t" >/dev/null 2>&1 || exit 1
done; then
  grn "doctor: toolchain complete"
else
  red "doctor: missing tools above — gates for those stages will BLOCK, not skip."
  exit 1
fi
