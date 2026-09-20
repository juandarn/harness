#!/usr/bin/env bash
# Shared helpers for gates/, adapters/ and bin/.
set -euo pipefail

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export HARNESS_ROOT

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }

# fail-loud: a gate whose tool is absent must BLOCK, never skip. A skipped
# check reads as green — a silent lie in the pipeline.
require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    red "GATE BROKEN: '$1' is missing. Run bin/doctor.sh — do not bypass."
    exit 1
  }
}

manifest() { printf '%s/harness.toolchain.yaml' "$HARNESS_ROOT"; }

# threshold KEY -> value from the pinned manifest
threshold() {
  awk -v k="$1" '$1==k":" {print $2; exit}' "$(manifest)"
}
