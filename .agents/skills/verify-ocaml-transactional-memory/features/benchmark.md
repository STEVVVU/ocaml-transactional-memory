# STM benchmark comparison

## Sub-features

Compare Kcas, TL2, and a coarse Mutex under disjoint, contended, and read-heavy bank workloads with matched operation counts.

## How to get to it (user POV)

Run the benchmark executable with its deterministic transfer schedule and evidence output directory.

## Driving it with the OCaml verification executable

Run `opam exec -- dune exec --profile release coursework/bench/stm_bench.exe -- --output .agents/runs/<run-id>/bench.csv`.

## Gotchas

Keep every raw sample. Interleave backend order, report retries and tail latency, and make no speedup claim without repeated native runs.
