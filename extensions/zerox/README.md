# ZeroX

ZeroX extends [Zerolang](https://github.com/vercel-labs/zerolang) through its
graph-first workflow. The upstream compiler and Apache-2.0 license are
retained. This extension is based on upstream commit
`7e1a64d27cc37671df31c6370890bce86f5135e1`.

## Go scalar proof of concept

The checked-in [zero.graph](go-scalar/zero.graph) calls one Go function with
two signed 64-bit arguments and checks the result. Zero's existing C header
import exposes the signature in `zero inspect --json`. The direct native
backend links the cgo-generated archive through
[zero.toml](go-scalar/zero.toml).

Run from the repository root with Node 24, make, a C compiler and a cgo-capable
Go 1.24+ toolchain. The Go smoke test targets Linux x86-64 with glibc.

```sh
make -C native/zero-c
bash extensions/zerox/scripts/smoke-zero.sh
bash extensions/zerox/scripts/smoke-go-scalar.sh
```

The Go smoke test builds in a disposable directory. It generates the ABI
binding twice and requires identical files, checks the generated declarations
against cgo's header, and runs the native executable built from `zero.graph`.
It also tests rejection of incompatible Zero arguments, unsupported and
generic Go signatures, and process termination on an uncaught Go panic.

To generate the fixture binding from `extensions/zerox`, choose a new output
directory:

```sh
go run -mod=readonly ./cmd/zerox-bindgen -package ./go-scalar -symbol Add -out /tmp/zerox-binding
```

The generator loads a Go package through `go/packages` and checks the
exported signature with `go/types`. It emits `binding.json`, `bridge.go`,
and `zerox_go.h` for one `func(int64, int64) int64` per invocation. The
fixture uses the fixed C symbol `zerox_go_add`. The metadata records a
dependency's resolved module version or `local` for the current module.
Build the generated wrapper from the same Go module so dependency resolution
uses the same `go.mod` and `go.sum`.

The native executable links the Go runtime. Treat imported Go calls as foreign
code with process-level effects. An uncaught Go panic terminates the process.
The pure Zero smoke test requires no Go toolchain.

See [architecture](docs/architecture.md) and [milestones](docs/milestones.md)
for proposed follow-on work.
