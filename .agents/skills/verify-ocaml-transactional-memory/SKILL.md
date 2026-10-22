---
name: verify-ocaml-transactional-memory
description: Verify the OCaml 5 transactional-memory examples and experimental TL2 backend on the real native executable.
---

# Verification status

This driver is a draft until it has been run on native OCaml 5. The current Windows host has no `ocamlc`, `opam`, or `dune`; do not substitute a simulator or OCaml 4. The checked-in Ubuntu CI job is the required native runner.

## Launch

From the repository root, resolve dependencies with `opam install . --deps-only --with-test`, record that exact resolution with `opam lock --keep-local .`, then run `opam install . --deps-only --with-test --locked`. Run `opam exec -- dune build @all` and `opam exec -- dune runtest`. The real coursework executable is `coursework/bin/stm_verify.exe` after a successful build. Invoke `opam exec -- dune exec coursework/bin/stm_verify.exe -- --evidence .agents/runs/<run-id>` for an isolated run. A successful run exits zero and prints a final JSON object with `passed: true`. A failure exits nonzero and writes a `passed: false` result before returning.

## Doctor

Run `opam exec -- dune exec coursework/bin/stm_verify.exe -- --doctor`. Doctor checks OCaml major version 5 and confirms that the verification executable starts. It reads only; it does not start worker domains or mutate test state. Drive separately checks that the requested evidence path stays under `.agents/runs/`.

## Drive

Run `opam exec -- dune exec coursework/bin/stm_verify.exe -- --evidence .agents/runs/<run-id>`. The driver creates fresh bank cells, starts real OCaml domains at 1, 2, and 4 workers, and checks transfer completion and total-balance conservation across Kcas, TL2, and Mutex. `dune runtest` separately drives deterministic conflicts and checks concurrent histories against an independent serial specification, including a fractured-history negative control.

## Evidence

Capture the command, exit code, stdout/stderr, JSON verdict, transfer count, domain count, and retry count in `.agents/runs/<run-id>/`. The proof must come from the executable built from this checkout. A verifier failure must leave a durable `passed: false` report with `cleanup_complete: true`. Raw benchmark samples are produced by `opam exec -- dune exec --profile release coursework/bench/stm_bench.exe -- --output .agents/runs/<run-id>/bench.csv`; report all interleaved Kcas, TL2, and Mutex samples without promising a speedup.

## Cleanup

The driver joins every domain it creates before exit. Delete only the run directory named on the command line after confirming the verifier process has ended. Confirm the JSON result and stdout survive cleanup. To test a deliberate post-launch failure, run `opam exec -- dune exec coursework/bin/stm_verify.exe -- --inject-failure --evidence .agents/runs/<failure-id>` and confirm a nonzero exit with `passed: false` in `verification.json`.

## Helpers

The maintained helper is `coursework/scripts/verify.sh`, invoked from the repository root as `bash coursework/scripts/verify.sh <run-id>`. It builds and drives one verification run, stores evidence under `.agents/runs/`, and returns the driver's exit status. It must not delete evidence.
