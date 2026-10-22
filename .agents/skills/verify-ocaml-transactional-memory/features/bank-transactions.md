# Transactional bank operations

## Sub-features

Transfer between two accounts, read a consistent total, and compare conservation across Kcas, TL2, and an explicit Mutex control.

## How to get to it (user POV)

Run the verification executable on a fresh set of accounts.

## Driving it with the OCaml verification executable

Run `opam exec -- dune exec coursework/bin/stm_verify.exe -- --evidence .agents/runs/<run-id>`.

## Gotchas

The bounded tests prove only the checked workload and domain counts. They do not establish starvation-freedom or a speedup.
