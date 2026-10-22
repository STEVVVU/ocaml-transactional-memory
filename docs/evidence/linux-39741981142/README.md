# Complete longer mixed STM sweep

[Native run 39741981142](https://github.com/STEVVVU/ocaml-transactional-memory/actions/runs/39741981142)
passed at source `995cb12f753e82b0a1eedb1ef8649487f2158e76` on Ubuntu 24.04,
OCaml 5.3.0, Dune 3.24.2, release mode, AMD EPYC 7763 VM, four logical CPUs
on two cores. The runner reported 16.76 GB RAM and 90.22 GB free disk before
the sweep. Installed packages and both opam lock files remain in the artifact.

This completes the frozen mixed workload's coverage. It is not a matched
before/after performance comparison. The previous failed 900-second run used
an Intel Xeon 8370C VM; the controlled pure-read-only comparison used an AMD
EPYC 9V74 VM and a different fixture. No causal timing comparison across those
hosts or workloads is made. The larger timeout is an execution envelope,
not a runtime optimization. The runtime, benchmark and tests are identical
to `51c48e5`; only GNU time placement and the tier cap changed in the helper.

## Frozen command and acceptance

With the native dependencies installed, from the repository root:

```sh
bash coursework/scripts/verify.sh --metrics fresh-long-mixed
```

The helper builds/drives the native verifier before the release benchmark.
Its three measured tier commands are equivalent to:

```sh
for pairs in 1 64 4096; do
  /usr/bin/time -v -o ".agents/runs/fresh-long-mixed/metrics-$pairs.resources.txt" \
    timeout 1200 _build/default/coursework/bench/stm_bench.exe \
    --output ".agents/runs/fresh-long-mixed/metrics-$pairs.csv" \
    --operations 20000 --pairs "$pairs" --domains 1,2,4 \
    --warmup 1000 --latency-stride 100
done
python3 coursework/scripts/summarize_metrics.py .agents/runs/fresh-long-mixed
```

Each tier uses all three backends and workloads at 1/2/4 domains. Five trials
rotate backend order by trial. Every domain performs 20000 measured operations
after 1000 serial warmup operations. Disjoint banks have separate pair groups
per domain (up to 32768 accounts); contended and read-heavy banks share the
group (up to 8192 accounts). Read-heavy performs one transfer and nine full
bank snapshots per ten operations. Warmup, allocation, domain creation and
the final conservation check sit outside each reported timed region; the
whole-tier GNU time receipt includes them. This is a closed-loop synthetic
workload, not offered-rate service latency or a coordinated-omission correction.

All 405 trial summaries completed: 81 groups with exactly trials 0..4, each
with zero errors and successes equal to operations. Independently calling the
maintained summarizer reproduced the artifact's `metrics-summary.json`
exactly. Coverage totals 18900000 measured successes and 189000 stride-100
latency rows, with the expected 200/400/800 samples per 1/2/4-domain trial.
Every summary value and retained latency is finite; operation schedules,
account counts, ordered p50/p95/p99 and throughput rounding were checked.

The benchmark computes quantiles from every operation, including errors,
before subsampling the raw latency stream. These retained samples cannot
independently reconstruct the full quantiles. Conservation is checked after
each trial and any error causes native nonzero exit. Zero errors therefore
includes no reported rejection, exception, retry exhaustion or conservation
failure in this bounded campaign; it is not a formal correctness proof.

The upstream/coursework Dune suite passed, including TL2 conflict tests and
the concurrent bank-history oracle. The native driver completed 5250 checked
transfers with owned-domain cleanup. Its deliberate failure control retained
passed=false and cleanup_complete=true. The separate short benchmark retained
135 summaries, 315000 successes and all 315000 latencies, zero errors. A
separate strace diagnostic completed 135 summaries/1575000 successes, zero
errors; its instrumented times are excluded from native comparisons. Metrics
have their own passed=true, exit_code=0 receipt; functional success alone
does not certify the sweep. Cleanup means joined owned domains/resources;
raw evidence was deliberately retained.

## Complete results and remaining costs

[All 81 cells](all-cells.md) report median and full minimum..maximum across
five trials, including every backend and slower case. [summary.csv](summary.csv)
also retains p50/p95, process CPU, allocations and short flags with full CSV
precision. [trial-summaries.csv](trial-summaries.csv) retains all 405 original
summary records and GC deltas; [coverage.csv](coverage.csv) proves every group.
68 groups contain at least one trial below 0.1 seconds. They provide bounded
correctness/latency observations, not strong throughput or scaling claims.

The longer 8192-account read-heavy cells give the following aggregate
operations/second, median (full trial range):

| Domains | Kcas | TL2 | Mutex |
| ---: | ---: | ---: | ---: |
| 1 | 4929.630 (4908.870..4993.283) | 750.446 (745.335..774.894) | 25463.049 (25025.170..26138.600) |
| 2 | 8639.479 (8577.324..8729.851) | 1184.980 (1173.950..1204.109) | 26597.382 (25616.005..27072.985) |
| 4 | 4714.115 (4705.671..4762.583) | 1009.185 (994.690..1020.794) | 21436.215 (21143.248..22030.061) |

All three backends have lower aggregate throughput at four domains than at
two in this shared mixed workload. TL2 remains slower than both controls.
The pure-read-only fast path does not remove mixed transactions' allocations
or concurrent invalidations. TL2 read-heavy details:

| Domains | Elapsed seconds | p99 microseconds | Retry events | Allocated words |
| ---: | --- | --- | --- | --- |
| 1 | 26.651 (25.810..26.834) | 2136.415 (2005.678..2197.950) | 0 (0..0) | 2362056193 (2362054325..2362074262) |
| 2 | 33.756 (33.220..34.073) | 3844.644 (3766.719..3883.301) | 3709 (3681..3720) | 5136109052 (5130381757..5137946575) |
| 4 | 79.272 (78.370..80.427) | 14280.403 (13873.921..14468.167) | 21651 (21490..21782) | 11823413700 (11804427213..11839029371) |

The bounded TL2 retry limit remains 100 attempts per transaction, with the
same Backoff behavior; 378519 retry events occurred across the entire matrix.
Aggregate retry events can exceed 100 because they sum many transactions.
They do not distinguish read/write causes or record each operation's maximum.
Kcas abort counts are not recorded; its zero TL2-retry field does not mean
zero Kcas aborts. All 90 large-tier disjoint/contended write-bearing trials
completed; TL2 p99 spans 2.385..3.858 microseconds and large contended
four-domain retries span 0..76. Those trials are short, and do not establish
a write-path improvement. No retry bound or ownership behavior was changed.
This does not establish fairness, starvation freedom, general workloads,
transactional abort classification or cache/NUMA effects.

## Whole-tier resources and identity

| Pairs | Wall seconds | User + system CPU seconds | Peak RSS KiB | Exit |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 4.14 | 6.28 + 1.11 | 26896 | 0 |
| 64 | 9.31 | 19.61 + 1.31 | 28520 | 0 |
| 4096 | 926.80 | 2438.23 + 18.38 | 65968 | 0 |

GNU time wraps `timeout 1200`, so costs include the timeout supervisor and
the whole benchmark process, all backends/trials, warmups, domain creation,
CSV output and final checks. These are single tier resource receipts, not
five repeated process measurements or per-transaction RSS. The large tier's
completed timed regions sum to 856.809844 seconds; the remainder includes
untimed work. Completion at 926.80 seconds under this envelope does not
explain absolute timing changes between hosts.

[receipt.json](receipt.json) preserves distinct functional, negative and
metrics verdicts. [resources.csv](resources.csv) preserves exact GNU commands
and costs. [raw-sha256.txt](raw-sha256.txt) hashes all 27 downloaded files,
including the primary hosted job log and lock files. [source-sha256.txt](source-sha256.txt)
hashes seven exact Git blobs at the recorded source (native runtime, workload,
test, helper, summarizer and workflow). The existing full-sweep driver did not
capture an executable hash; this limitation is explicit, and no binary identity
is invented. Source, native build command and environment are retained.

The [earlier false-124 receipt and incomplete rows](../linux-39739124466/),
original failed sweep/profiles, and [accepted same-runner pure-read-only
comparison](../linux-39735999046/) remain intact. That controlled comparison
supports the scoped read-only improvement. This full mixed sweep supplies
the previously missing coverage and exposes remaining latency/retry costs;
it supplies no additional causal speedup claim.
