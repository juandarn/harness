#!/usr/bin/env bash
# Shared helpers for gates/. Ported from rigor-harness gates/lib.sh, trimmed
# to require_tool + color helpers (manifest/threshold only served quality-pipeline).
set -euo pipefail

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }

# fail-loud: a gate whose tool is absent must BLOCK, never skip. A skipped
# check reads as green — a silent lie in the pipeline.
require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    red "GATE BROKEN: '$1' is missing. Install it — do not bypass."
    exit 1
  }
}
