#!/usr/bin/env bash
set -euo pipefail

legacy_hits=$(rg -n --no-heading -e '\b(?:SKU|CFG)-' . || true)

if [[ -n "${legacy_hits}" ]]; then
  echo "Legacy identifier prefixes found (expected none):" >&2
  echo "${legacy_hits}" >&2
  exit 1
fi

echo "No legacy identifier prefixes found."
