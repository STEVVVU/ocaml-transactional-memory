# TL2 conflict handling

## Sub-features

Read-your-writes, rollback on user exceptions, snapshot validation after commit-version reservation, sorted write-lock acquisition, partial-lock release, prepublication failure atomicity, bounded retries, and read-only snapshots.

## How to get to it (user POV)

Run the verification executable with the native OCaml 5 runtime.

## Driving it with the OCaml verification executable

Run `opam exec -- dune exec coursework/bin/stm_verify.exe -- --evidence .agents/runs/<run-id>`.

## Gotchas

The backend supports integer cells only. It is a paper-inspired experiment, not a formal proof of TL2 or a replacement for Kcas.
