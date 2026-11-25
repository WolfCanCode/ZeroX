# Milestones

- [ ] M0: fork upstream, record base commit, build local compiler and run baseline native tests and graph smoke test.
- [x] M1: manually bridge a deterministic Go `int64` function to Zero through the supported C ABI; prove result via an executable test. Test rejection of invalid signatures. Verify target-specific link behavior and panic policy.
- [ ] M2: create Go dependency indexer using go/packages and go/types. Export versioned metadata and reject unsupported types explicitly. Build generated wrappers deterministically.
- [ ] M3: make indexed symbols discoverable by an agent and callable through checked Zero graph operations. Add a stale-patch test, type mismatch test and an external-effects policy. Verify that pure Zero still builds without Go.
- [ ] M4: add a real dependency with a small, well-defined contract. Extend strings/buffers only after designing allocation/free ownership and error mapping.
- [ ] M5: benchmark small-model performance, with reproducible tasks and honest baselines.

Non-goals for the initial milestone: new graph storage, a second compiler, universal multi-language runtime, automatic support for arbitrary dependencies, production claims.
