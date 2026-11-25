# Architecture decisions (proposed)

## ADR-001: Extend rather than replace Zero

Keep the upstream compiler, graph format, graph patch engine, semantic checks, MIR and native code generation. Place initial extensions under `extensions/zerox`. Preserve upstream license and attribution. Change core only when external symbol integration demonstrably requires it. Keep upstream/main as a merge reference.

## ADR-002: Native-first, foreign runtimes opt-in

Index Go exported symbols using golang.org/x/tools/go/packages and go/types, initially a narrow scalar subset. Produce deterministic metadata (package path, module version, target, symbol, types, ABI mapping and effect annotations). Generate cgo wrappers and a C-compatible library/header. Use the existing Zero interoperability pathway where possible. Do not silently treat unknown external effects as pure. Reject unsupported types, callbacks, panic propagation and ownership patterns until an explicit contract exists. A Go-linked application carries the Go runtime; a pure Zero application should not.

## ADR-003: Canonical graph stays canonical

Dependency metadata is a read-only index, not a second application graph. Use checked Zero operations to author calls; never mutate zero.graph directly. The first milestone may use a sidecar index with explicit references to native extern bindings, if the current graph interface does not support imported symbols. Document that limitation. Generated wrappers are build artifacts. Resolve and pin module versions; use isolated build workspaces and treat third-party code as untrusted.

## ADR-004: Measure before optimizing

Use equivalent tasks, pinned models, fixed budgets and multiple trials. Compare text-based Go, stock Zero where the task is feasible, and ZeroX. Report task success, input/output tokens, tool calls, retries, wall-clock latency, binary size and peak memory. Do not infer business correctness from successful compilation.
