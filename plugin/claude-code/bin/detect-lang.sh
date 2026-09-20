#!/usr/bin/env bash
set -euo pipefail
case "${1##*.}" in
  go)            echo go ;;
  kt|kts)        echo kotlin ;;
  ts|tsx|js|jsx) echo ts ;;
  py)            echo py ;;
  *)             echo unknown ;;
esac
