# Incomplete longer mixed-sweep rerun: 900-second tier limit

[Run 39739124466](https://github.com/STEVVVU/ocaml-transactional-memory/actions/runs/39739124466)
FAILED at source `51c48e58bf36944ed4635975e61f82df09598e5e`. The upstream/
coursework suite, native functional driver, deliberate failure control and
default short benchmark passed before the optional frozen metrics step.
The dedicated metrics receipt correctly records passed=false, exit_code=124;
the functional receipt does not certify this failed metrics campaign.

Primary failed-step log shows the 64-pair command completed at
07:18:23.331 UTC and the process exited 124 at 07:33:23.362 UTC on 2026-10-22.
The following 4096-pair command has an unchanged 900-second timeout. This
confirms the failure mechanism is its cumulative tier wall limit. No reported
operation error or retry exhaustion appears in completed rows. Nothing
certifies operations inside the interrupted/unreported invocation.

Unchanged frozen input: 20000 operations/domain, 1000 serial warmups/domain,
five rotated backend trials, 1/2/4 domains, pairs 1/64/4096 and latency stride
100. Disjoint banks allocate a pair group per domain; read-heavy/contended
banks share the group. Read-heavy scheduling performs one transfer followed
by nine complete bank snapshots in every ten operations. Runtime retry limits
and the write-bearing lock/version/publication protocol were unchanged.

| Pairs | Completed trial summaries | Reported completed-row errors |
| ---: | ---: | ---: |
| 1 | 135/135 | 0 |
| 64 | 135/135 | 0 |
| 4096 | 132/135 | 0 |

`coverage.csv` lists all 81 backend/workload/domain/account-tier groups:
78 have all five trials; three have only trials 0..3. Missing trial 4 is
read-heavy/four-domain for Kcas, TL2 and Mutex. The next invocation in the
unchanged rotation is TL2, followed by Mutex then Kcas; the log does not show
whether that TL2 invocation was in setup, warmup or its timed loop at termination.
The following two backend invocations could not have completed. No duration or
operation count is invented for unfinished work.

`completed-summaries.csv` preserves all 402 raw summary rows without promoting
the partial matrix to an accepted summary. They account for 18660000 completed
operations/successes with zero reported errors; 186600 stride-100 latency rows
remain in raw evidence. Additional work in the interrupted invocation is
unknown. The maintained summarizer was called directly as a local parser
check and rejected the artifact with
`AssertionError(('kcas', 'read-heavy', '4', '8192'))`. No native test or timing
was run locally and no accepted metrics-summary was produced.

The large tier already contains 807.552485 seconds of completed timed regions.
That excludes its serial warmups, final total checks and unfinished invocation.
All 90 disjoint/contended large-tier trial summaries completed with zero errors.
TL2's completed write-bearing large-tier cases span p99 0.824..1.711 µs;
its contended four-domain retry counts range 14..878, with no exhausted run.
These are observed bounded rows, not a cross-run write-path improvement claim.

Completed TL2 read-heavy rows differ from the pure read-only
snapshots: five two-domain trials take 34.823..35.626 seconds with 3703..3749
retries; four completed four-domain trials take 86.797..91.650 seconds with
21479..21741 retries and p99 17.506..18.781 ms. Four-domain allocations are
11.793..11.822 billion words per completed trial. Those four trials cannot
stand in for the required five. The earlier same-runner read-only improvement
remains scoped to snapshots without concurrent writers; these mixed rows do
not establish a matched before/after effect on write-bearing retries/latency.

This runner reports Intel Xeon Platinum 8370C, four logical CPUs, with OCaml
5.3.0. It differs from the AMD runner used for the controlled read-only pair.
Do not compare absolute times across those runs as a causal speedup. The
failed large-tier resource log is empty because timeout wraps GNU time and
terminates that child too; complete-tier RSS/CPU is therefore unavailable.
Successful small-tier resource logs remain retained. Binary SHA-256 was not
recorded by this existing sweep path; source identity and native build step
are retained without inventing a binary identity.

Minimal next step is a bounded 1200-second tier envelope with every workload,
operation count, warmup, trial, backend, retry bound and validator unchanged.
The remaining observed trial costs plus untimed work explain why the old
cumulative budget is insufficient; more time is not a runtime correctness fix
or a guarantee of completion. Main subsequently implemented that envelope and
placed GNU time outside timeout in `995cb12`, so future failures retain
resources. No workload was reduced and no four-repeat group was accepted.
No runtime or harness source was changed by the worker during this audit.

`receipt.json` preserves the false verdict. `raw-sha256.txt` covers every
downloaded artifact file and the primary failed-step log. Original baseline,
failed profile and accepted matched read-only evidence remain intact.
