#!/usr/bin/env bash
# usage: artifact-gate.sh <PHASE> <change-dir>
# Ported from rigor-harness gates/artifact-gate.sh (unchanged logic).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PHASE="${1:?usage: artifact-gate.sh <PHASE> <change-dir>}"
DIR="${2:?change-dir required}"

case "$PHASE" in
  INTAKE)  doc=brief.md ;;
  EXPLORE) doc=findings.md ;;
  SPEC)    doc=PRD.md ;;
  DESIGN)  doc=ARCH.md ;;
  TASKS)   doc=PLAN.md ;;
  QUALITY) doc=quality-report.md ;;
  VERIFY)  doc=verdict.md ;;
  *)       grn "no artifact required for phase $PHASE"; exit 0 ;;
esac

if [ -s "$DIR/$doc" ]; then
  grn "artifact ok: $PHASE -> $doc"
else
  red "MISSING artifact: $PHASE must produce '$doc' in $DIR before advancing."
  exit 1
fi
