# STM benchmark comparison

## Sub-features

Compare Kcas, TL2, and a coarse Mutex under disjoint, contended, and read-heavy bank workloads with matched operation counts.

## How to get to it (user POV)

Run the benchmark executable with its deterministic transfer schedule and evidence output directory.

## Driving it with the OCaml verification executable

Run `opam exec -- dune exec --profile release coursework/bench/stm_bench.exe -- --output .agents/runs/<run-id>/bench.csv`.

## Gotchas

The hosted workflow's optional `metrics` input drives the maintained helper as
`bash coursework/scripts/verify.sh --metrics <run-id>`. It builds release mode,
records source/environment, rotates all three backends five times, sweeps
1/2/4 domains capped at available CPUs and 1/64/4096 account pairs, and offers
20000 operations per domain after 1000 serial warmup operations per domain.
Disjoint workloads use a separate pair group per domain; the other workloads
share the group. Read-heavy totals visit the entire shared group.

Summary tails use every operation, including failures. Raw latency rows retain
every 100th operation in this larger campaign; `latency_stride` labels that
subsample. Default short verification still retains all latency rows. Summary
adds account count, process CPU, allocated words and GC collection deltas.
TL2 retries count only TL2 retries, not Kcas aborts. Any recorded failure causes
nonzero exit after writing its CSV. The validator requires five complete trials
with zero errors before producing median/range output. Short trials are flagged
for longer followup, not advertised as representative throughput.
Process CPU/RSS comes from `/usr/bin/time -v`; a separate unreported strace run
captures synchronization/system-call behavior. Neither measures fairness or
cache/NUMA effects. Retry limits, backend semantics and tests are unchanged.

Both `--metrics` and `--profile` initialize `metrics-result.json` as false and
install an EXIT receipt before starting native commands. A nonzero timeout,
driver, benchmark, validation or profiler exit retains a false metrics verdict.
`verification.json` remains functional evidence and cannot certify metrics.

The separate workflow `profile_only=true` path runs the same 8192-shared-account
read footprint with 100 operations, one domain, zero warmup and all five backend
rotations under a 300-second Callgrind limit. All backends/workloads remain
present. Raw instruction profile, annotation and per-operation correctness data
are retained. Its instrumented timing data is excluded from comparisons.

Keep every raw sample. Interleave backend order, report retries and tail latency, and make no speedup claim without repeated native runs.
