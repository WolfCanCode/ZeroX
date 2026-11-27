# Milestones

- [ ] M0: fork upstream, record base commit, build local compiler and run baseline native tests and graph smoke test.
- [x] M1: manually bridge a deterministic Go `int64` function to Zero through the supported C ABI; prove result via an executable test. Test rejection of invalid signatures. Verify target-specific link behavior and panic policy.
- [x] M2: discover one exported Go function with go/packages and go/types. Emit versioned metadata, a deterministic wrapper and a C header for the signed 64-bit fixture. Reject unsupported signatures.
- [x] M3: discover the indexed symbol against a package graph and plan a typed foreign call with explicit consent. Verify stale patch and type rejection and run pure Zero without Go.
- [ ] M4: add a real dependency with a small, well-defined contract. Extend strings/buffers only after designing allocation/free ownership and error mapping.
- [ ] M5: benchmark small-model performance, with reproducible tasks and honest baselines.

Non-goals for the initial milestone: new graph storage, a second compiler, universal multi-language runtime, automatic support for arbitrary dependencies, production claims.
