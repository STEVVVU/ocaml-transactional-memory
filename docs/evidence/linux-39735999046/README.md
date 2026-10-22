# Matched native read-only validation result

[Run 39735999046](https://github.com/STEVVVU/ocaml-transactional-memory/actions/runs/39735999046)
completed successfully. Baseline source is
`6ecf556be3102730b6eef054c09c2a02aa279809`; candidate source is
`51c48e58bf36944ed4635975e61f82df09598e5e`. The only runtime-source difference
under coursework/src is the eight-line read-only commit branch. The original
write-bearing lock/version/publication path and retry bounds remain unchanged.
Main and an independent reviewer approved that branch before this native run.

Ubuntu 24.04, OCaml 5.3.0, Dune 3.24.2, multicore-bench 0.1.7, Release build;
AMD EPYC 9V74 VM with four logical CPUs, two reported cores, one NUMA node.
The existing installed package resolution is common to both builds and retained
in the environment file. Fixture SHA-256 for both builds:
`18da6045b3de941af9a17c8662cf10b0e51c6cdb2e8968ad33ebedae4824a2c7`.
It also matches the committed candidate fixture's exact Git blob.

Candidate binary SHA-256:
`0172d621b1e0e2fa541a5d976dd989100031db38af80722873cb845fb1684512`.
Baseline binary SHA-256:
`a22c990593a8c1c4cab43a8ee43de38b9756f0f1246e0915d2b6681e33b4a2d9`.
The baseline was archived from its frozen commit, then received an identical
copy of the maintained candidate fixture before building. Its source-archive
hash is retained too. This explicitly changes the original 100-snapshot
baseline to 1000 snapshots per domain for BOTH builds. The original run
39733269312 remains retained and is not the comparator for this result.

Reproduce using `framework=true` in the maintained coursework workflow at
candidate source. It builds/tests current source, archives frozen source,
copies and checks the fixture, builds/tests the baseline, then alternates five
whole passes per build. Each invocation uses the framework's synchronized
domain start, three warmups, five native runs and randomized suite order:

```sh
opam exec -- dune build --profile release coursework/bench/stm_framework.exe
/usr/bin/time -v -o resources.txt timeout 180 \
  _build/default/coursework/bench/stm_framework.exe > framework.json
```

All backends use 8192 accounts and 1000 Bank.total snapshots per domain; every
snapshot must equal 8192000000. The actual order was baseline/candidate,
candidate/baseline, baseline/candidate, candidate/baseline, baseline/candidate.
Exact per-pass commands, raw native JSON/stderr, GNU time resources and exit
receipts remain in the artifact. Every process exited zero with empty stderr.
The dedicated terminal receipt is true with cleanup_complete=true; only the
task-owned temporary baseline checkout was removed. Evidence survives cleanup.

`framework-passes.csv` retains all 180 native aggregate metric records: ten
passes, nine backend/domain cases and two metrics. Every expected case occurs
once per pass; every metric has five runs, finite positive value/best/mean/
median and finite nonnegative SD. The native framework does not emit individual
inner timings. `summary.csv` gives 18 summaries across the five pass medians;
`comparison.csv` contains every baseline/candidate control. Ranges below are
the full range of pass medians, not the range of all 25 inner timings.

| Backend/domains | Baseline snapshots/s | Candidate snapshots/s | Ratio |
| --- | ---: | ---: | ---: |
| Kcas/1 | 6446.9 (6409.1..6615.8) | 6514.9 (6463.0..6641.3) | 1.011 |
| Kcas/2 | 11716.8 (11609.2..11871.5) | 11756.8 (11341.6..11893.7) | 1.003 |
| Kcas/4 | 12695.2 (12643.9..12865.5) | 12993.9 (12910.0..13057.8) | 1.024 |
| TL2/1 | 378.2 (359.1..380.4) | 935.2 (926.8..938.0) | 2.473 |
| TL2/2 | 643.6 (629.3..663.8) | 1524.4 (1517.8..1535.4) | 2.368 |
| TL2/4 | 862.8 (851.1..875.1) | 1963.6 (1913.2..1993.4) | 2.276 |
| Mutex/1 | 26474.1 (24729.2..26796.6) | 24071.6 (23371.1..24698.4) | 0.909 |
| Mutex/2 | 37202.4 (34953.4..37621.9) | 33890.3 (32474.6..35803.2) | 0.911 |
| Mutex/4 | 28402.4 (26991.9..29252.9) | 27984.5 (26187.6..28716.3) | 0.985 |

TL2's pass-median ranges are disjoint in every domain case. The approximately
9% lower unchanged Mutex one/two-domain controls remain visible; their cause
was not isolated. No backend-independent, fairness or cache/NUMA claim follows.
The `ns` metric is domain time per snapshot, while `M/s` is aggregate throughput;
do not invert the former as global throughput at multiple domains.

`resources.csv` retains all ten full-process rows. Whole-pass median (range)
wall time is 90.95 (90.13..91.89) seconds baseline versus
42.93 (42.35..43.04) candidate. Total process CPU is
249.31 (249.00..253.45) versus 120.78 (119.16..121.35) seconds. Peak RSS is
39396 (37272..43796) versus 50104 (49120..50712) KiB. Resource scope includes
all backends, all warmups, domain creation and the framework; the RSS increase
is not hidden or attributed to a specific backend without further evidence.

The hosted primary job log confirms the candidate upstream/coursework suite,
new stale/same-value read rejection checks, 1/2/4-domain increments and unchanged
concurrent bank-history oracle completed. The archived baseline suite also
passed. Functional verification records 5250 successful transfers and cleanup;
the deliberate failure records false with its exact injected detail and
cleanup. Independently audited short bench.csv has 135 summaries and all
315000 operation latency rows, 315000 successes and zero errors. This separate
short mixed campaign is correctness/bounded coverage, not the full longer
mixed/latency/retry/working-set sweep that previously timed out.

`raw-sha256.txt` covers every downloaded artifact file and the retained primary
hosted job log. Original failed campaign/profile receipts remain intact in
their separate stores. No local native build/timing or duplicated hosted test
was performed for this audit. Remaining long mixed-workload coverage must be
reported separately; no short or partial result substitutes for it.
