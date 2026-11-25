#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
extension="$repo/extensions/zerox"
fixture="$extension/go-scalar"
zero=${ZERO_BIN:-"$repo/bin/zero"}
[[ "$zero" = /* ]] || zero="$PWD/$zero"
[[ "$(uname -s):$(uname -m)" = Linux:x86_64 && "$(getconf GNU_LIBC_VERSION)" = glibc* ]] || {
  echo 'The Go FFI smoke test requires Linux x86-64 with glibc.' >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GOCACHE="${GOCACHE:-$work/go-cache}"
export GOPATH="${GOPATH:-$work/go-path}"
export GOTOOLCHAIN=local GOWORK=off GOOS=linux GOARCH=amd64 CGO_ENABLED=1 CC=cc
mkdir -p "$work/app/abi" "$work/module/go-scalar" "$work/module/cmd"
cp "$fixture"/{zero.graph,zero.toml} "$work/app/"
cp "$fixture/add.go" "$work/module/go-scalar/"
cp "$extension"/{go.mod,go.sum} "$work/module/"
cp -R "$extension/cmd/zerox-bindgen" "$work/module/cmd/"

cd "$work/module"
go build -buildvcs=false -mod=readonly -o "$work/zerox-bindgen" ./cmd/zerox-bindgen
"$work/zerox-bindgen" -package ./go-scalar -out "$work/binding"
"$work/zerox-bindgen" -package ./go-scalar -out "$work/repeat"
diff -r "$work/binding" "$work/repeat"

go build -buildvcs=false -mod=readonly -trimpath -buildmode=c-archive -o "$work/app/abi/libzerox_go.a" "$work/binding/bridge.go"
cp "$work/binding/zerox_go.h" "$work/app/abi/"
cd "$work/app"
# Check that the compiler-facing declaration matches cgo's generated ABI.
printf '#include "zerox_go.h"\n#include "libzerox_go.h"\n' | cc -Iabi -x c -fsyntax-only -

"$zero" inspect --json --target linux-x64 . > "$work/inspect.json"
"$zero" build --json --backend direct --target linux-x64 --out ./go-scalar . > "$work/build.json"
./go-scalar
node --input-type=module - "$work/inspect.json" "$work/build.json" "$work/binding/binding.json" <<'JS'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const [inspection, build, metadata] = process.argv.slice(2).map(path => JSON.parse(readFileSync(path)))
const binding = inspection.cImports.find(entry => entry.alias === 'goABI')
const fn = binding.typedModel.functions.find(entry => entry.name === 'zerox_go_add')
assert.equal(metadata.schemaVersion, 1)
assert.equal(metadata.package, 'github.com/WolfCanCode/ZeroX/extensions/zerox/go-scalar')
assert.equal(metadata.module, 'github.com/WolfCanCode/ZeroX/extensions/zerox')
assert.equal(metadata.moduleVersion, 'local')
assert.equal(metadata.goSymbol, 'Add')
assert.equal(metadata.abiSymbol, fn.name)
assert.equal(metadata.effects, 'foreign')
assert.deepEqual(metadata.parameters, ['int64', 'int64'])
assert.equal(metadata.result, 'int64')
assert.equal(metadata.abiType, fn.returnType)
assert.equal(metadata.target, build.target)
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

cd "$work/module"
cat >> go-scalar/add.go <<'GO'

func Wrong(left, right string) string { return left + right }

func Generic[T any](left, right int64) int64 { return left + right }
GO
for symbol in Wrong Generic; do
  if "$work/zerox-bindgen" -package ./go-scalar -symbol "$symbol" -out "$work/invalid" > "$work/invalid-go.log" 2>&1; then
    echo "Binding generator accepted unsupported symbol $symbol." >&2
    exit 1
  fi
  grep -F "unsupported signature" "$work/invalid-go.log" >/dev/null
  test ! -e "$work/invalid"
done
echo 'Go FFI: binding generator rejected unsupported signatures'

# An uncaught Go panic must terminate the process without a Zero return value.
printf 'package scalar\nfunc Add(left, right int64) int64 { panic("ZeroX panic smoke") }\n' > go-scalar/add.go
go build -buildvcs=false -mod=readonly -trimpath -buildmode=c-archive -o "$work/app/abi/libzerox_go.a" "$work/binding/bridge.go"
cd "$work/app"
"$zero" build --backend direct --target linux-x64 --out ./go-panic .
ulimit -c 0
if GOTRACEBACK=single ./go-panic > "$work/panic.log" 2>&1; then
  echo 'An uncaught Go panic unexpectedly returned success.' >&2
  exit 1
fi
grep -F 'panic: ZeroX panic smoke' "$work/panic.log" >/dev/null
echo 'Go FFI: uncaught Go panic terminated the subprocess'
