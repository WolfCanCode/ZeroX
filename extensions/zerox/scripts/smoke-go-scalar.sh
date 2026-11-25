#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fixture="$repo/extensions/zerox/go-scalar"
zero=${ZERO_BIN:-"$repo/bin/zero"}
[[ "$zero" = /* ]] || zero="$PWD/$zero"
[[ "$(uname -s):$(uname -m)" = Linux:x86_64 && "$(getconf GNU_LIBC_VERSION)" = glibc* ]] || {
  echo 'The Go FFI smoke test requires Linux x86-64 with glibc.' >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GOCACHE="${GOCACHE:-$work/go-cache}"
export GOTOOLCHAIN=local GOOS=linux GOARCH=amd64 CGO_ENABLED=1 CC=cc
mkdir -p "$work/app/abi"
cp "$fixture"/{zero.graph,zero.toml} "$work/app/"
cp "$fixture/zerox_go.h" "$work/app/abi/"
cd "$work/app"

go build -trimpath -buildmode=c-archive -o abi/libzerox_go.a "$fixture"/{add,bridge}.go
# Check that the compiler-facing declaration matches cgo's generated ABI.
printf '#include "zerox_go.h"\n#include "libzerox_go.h"\n' | cc -Iabi -x c -fsyntax-only -

"$zero" inspect --json --target linux-x64 . > "$work/inspect.json"
"$zero" build --json --backend direct --target linux-x64 --out ./go-scalar . > "$work/build.json"
./go-scalar
node --input-type=module - "$work/inspect.json" "$work/build.json" <<'JS'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const [inspection, build] = process.argv.slice(2).map(path => JSON.parse(readFileSync(path)))
const binding = inspection.cImports.find(entry => entry.alias === 'goABI')
const fn = binding.typedModel.functions.find(entry => entry.name === 'zerox_go_add')
assert.equal(fn.returnType, 'int64_t')
assert.deepEqual(fn.params.map(param => param.type), ['int64_t', 'int64_t'])
assert.equal(build.graph.artifact, './zero.graph')
assert.equal(build.target, 'linux-x64')
assert.equal(build.releaseTargetContract.selectedEmitter, 'zero-elf64')
assert(build.objectBackend.linkerPlan.staticLibraries.some(path => path.endsWith('/abi/libzerox_go.a')))
JS
echo 'Go FFI: graph-only native build and signed 64-bit result passed'

# Run a negative Zero check against a disposable projection.
"$zero" export .
sed -i 's/5000000000_i64/"invalid"/' src/main.0
if "$zero" import --json . > "$work/invalid-zero.json"; then
  echo 'Zero accepted a string at an int64_t ABI boundary.' >&2
  exit 1
fi
node --input-type=module - "$work/invalid-zero.json" <<'JS'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const result = JSON.parse(readFileSync(process.argv[2]))
assert(result.diagnostics.some(item => item.code === 'STD003' && item.message.includes('zerox_go_add')))
JS
cmp zero.graph "$fixture/zero.graph"
rm src/main.0
echo 'Go FFI: Zero rejected an incompatible call'

cat > "$work/add.go" <<'GO'
package main

func add(left, right string) string { return left + right }
GO
cp "$fixture/bridge.go" "$work/"
if go build -buildmode=c-archive -o "$work/invalid.a" "$work"/{add,bridge}.go > "$work/invalid-go.log" 2>&1; then
  echo 'Go accepted an unsupported bridge signature.' >&2
  exit 1
fi
grep -F 'func(int64, int64) int64' "$work/invalid-go.log" >/dev/null
echo 'Go FFI: Go rejected an incompatible bridge signature'

# An uncaught Go panic must terminate the process without a Zero return value.
printf 'package main\nfunc add(left, right int64) int64 { panic("ZeroX panic smoke") }\n' > "$work/add.go"
go build -trimpath -buildmode=c-archive -o abi/libzerox_go.a "$work"/{add,bridge}.go
"$zero" build --backend direct --target linux-x64 --out ./go-panic .
ulimit -c 0
if GOTRACEBACK=single ./go-panic > "$work/panic.log" 2>&1; then
  echo 'An uncaught Go panic unexpectedly returned success.' >&2
  exit 1
fi
grep -F 'panic: ZeroX panic smoke' "$work/panic.log" >/dev/null
echo 'Go FFI: uncaught Go panic terminated the subprocess'
