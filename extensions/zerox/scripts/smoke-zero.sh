#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
zero=${ZERO_BIN:-"$repo/bin/zero"}
if [[ "$zero" != /* ]]; then zero="$(pwd)/$zero"; fi
[[ -x "$zero" ]] || { echo "Build the upstream compiler or set ZERO_BIN to an absolute executable path." >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
"$zero" init
"$zero" patch --op 'addMain' --op 'addCheckWrite fn="main" text="hello from zero\n"'
"$zero" check
output=$("$zero" run)
printf '%s\n' "$output"
[[ "$output" == *"hello from zero"* ]]
