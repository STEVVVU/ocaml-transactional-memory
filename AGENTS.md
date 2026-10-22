# Project instructions

This repository preserves upstream Kcas and adds an isolated OCaml 5 STM comparison under `coursework/`. Keep coursework code, tests, benchmarks, and docs out of upstream `src/`, `test/`, and `bench/` unless a required shared fix is demonstrated.

## Build and test

Use OCaml 5 with Dune. From the repository root, resolve dependencies with `opam install . --deps-only --with-test`, record the installed resolution with `opam lock --keep-local .`, then run `opam install . --deps-only --with-test --locked`, `opam exec -- dune build @all`, and `opam exec -- dune runtest`. CI is the native verification path on hosts without an OCaml 5 toolchain. Never claim a local or hosted result unless the command output and exit status were observed.

For focused coursework checks, use the command documented in `.agents/skills/verify-ocaml-transactional-memory/SKILL.md`. Keep generated evidence outside the source tree under `.agents/runs/` and preserve it after cleanup.

## Scope and guarantees

Keep the experimental TL2 implementation separate from Kcas. It is a bounded integer-cell API, not a replacement for the general polymorphic Kcas API. Preserve the ISC license, upstream notices, and original repository history. Do not install tools into shared runtimes or change system security settings.
