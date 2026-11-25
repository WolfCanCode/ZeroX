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
Go toolchain. The Go smoke test targets Linux x86-64 with glibc.

```sh
make -C native/zero-c
bash extensions/zerox/scripts/smoke-zero.sh
bash extensions/zerox/scripts/smoke-go-scalar.sh
```

The Go smoke test builds in a disposable directory. It checks the cgo header
against the Zero-facing declaration, builds from `zero.graph`, and runs the
native executable. It also verifies that Zero rejects an incompatible call,
that Go rejects a change to the supported signature, and that an uncaught
Go panic terminates the subprocess.

The demo uses a handwritten cgo wrapper for `func(int64, int64) int64`. It
links the Go runtime into the executable. Treat imported Go calls as foreign
code with process-level effects. This fixture has no panic recovery or
translation into Zero errors. The pure Zero smoke test requires no Go
toolchain.

See [architecture](docs/architecture.md) and [milestones](docs/milestones.md)
for proposed follow-on work.
