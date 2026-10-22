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

GNU time now wraps `timeout 1200` separately for each account-pair tier and
writes `metrics-<pairs>.resources.txt`, retaining whole-tier CPU/RSS/wall/exit
even when timeout fails. This changes the execution budget and resource
capture only. The prior 900-second false-124 receipt remains retained at
`docs/evidence/linux-39739124466/`; its incomplete groups were rejected.
Native run 39741981142 completed the same matrix at 995cb12: 405 summaries,
81 complete five-trial groups, 18900000 successes/zero errors, 189000 retained
stride-100 latencies. The maintained summary reproduced exactly. All trials,
medians/full ranges, resources and hashes are in `docs/evidence/linux-39741981142/`.
68 groups contain short trials; do not turn these into throughput claims.
Full quantiles use all samples and cannot be reconstructed from stride-100
raw latencies. All three backends slow at four domains versus two in the
large shared read-heavy workload; TL2 still has substantial retry/allocation/
tail costs. The run establishes bounded mixed coverage, not a before/after
gain across hosts.

Both `--metrics` and `--profile` initialize `metrics-result.json` as false and
install an EXIT receipt before starting native commands. A nonzero timeout,
driver, benchmark, validation or profiler exit retains a false metrics verdict.
`verification.json` remains functional evidence and cannot certify metrics.

The separate workflow `profile_only=true` path runs the same 8192-shared-account
read footprint with 10 operations, one domain, zero warmup and all five backend
rotations under a 300-second Callgrind limit. All backends/workloads remain
present. Raw instruction profile, annotation and per-operation correctness data
are retained. Its instrumented timing data is excluded from comparisons.

The first 100-operation profile hit its 300-second limit after completing only
one Kcas read-heavy row. Its partial counters were dominated by OCaml runtime
GC coordination under Valgrind thread serialization, not a decisive TL2 CPU
profile. The followup preserves the account footprint and backend rotations,
reduces only diagnostic operations, uses supported fair thread scheduling and
dumps counters every billion basic blocks. See the profiler's
[thread scheduling](https://valgrind.org/docs/manual/manual-core.html#manual-core.opt.fair-sched)
and [counter dumping](https://valgrind.org/docs/manual/cl-manual.html#cl-manual.dumps)
documentation. Neither profile is a native timing comparison.

The optional `framework=true` workflow path reuses the already resolved
`multicore-bench` 0.1.7 dependency and its existing upstream fixture pattern.
`coursework/bench/stm_framework.exe` compares checked 8192-account read-only
snapshots across Kcas/TL2/Mutex and 1/2/4 recommended domains. The framework
owns domain launch, synchronized starts, three warmups, five measured runs,
random suite ordering and native JSON metrics. Five whole framework passes
retain interleaved backend comparisons. Its default extra untimed domain at
one worker keeps OCaml's multicore runtime enabled. This focused throughput
path supplements the existing mixed-workload latency/failure/retry probes;
it does not replace them or the full frozen baseline. No new engine/dependency.
See the installed version's
[public API](https://github.com/ocaml-multicore/multicore-bench/blob/0.1.7/lib/multicore_bench.mli).

After the original 100-snapshot baseline, the maintained fixture uses 1000
snapshots per domain to lengthen short Mutex controls. The hosted framework
path archives frozen source `6ecf556be3102730b6eef054c09c2a02aa279809`, copies
the identical current fixture into that baseline, builds/tests both sources
against the same installed resolution and alternates five whole passes per
build. Each pass retains native five-run/three-warmup statistics, GNU time
resources, its exact command and an exit receipt under a 180-second timeout.
An atomic terminal receipt and owned temporary-source cleanup cover earlier
build/test failures too. Source archive, fixture and executable hashes record
the explicit workload revision. Keep the original 100-snapshot evidence;
compare only the matched 1000-snapshot pair for improvement acceptance.

Keep every raw sample. Interleave backend order, report retries and tail latency, and make no speedup claim without repeated native runs.
