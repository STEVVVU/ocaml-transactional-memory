# Multicore-bench read-only baseline

[Run 39733269312](https://github.com/STEVVVU/ocaml-transactional-memory/actions/runs/39733269312)
passed at source `6ecf556be3102730b6eef054c09c2a02aa279809`. The unchanged
upstream/coursework suite, real-domain 5250-transfer verifier and intentional
failure control passed with owned-domain cleanup. No TL2 optimization is part
of this baseline.

Ubuntu 24.04, OCaml 5.3.0, Dune 3.24.2, multicore-bench 0.1.7, Release build;
AMD EPYC 9V45 VM, four logical CPUs on two reported cores, one NUMA node.
Framework binary SHA-256:
`7bde1dd3a5f63dba4cbf401b685ec3e34352b2e6e4bd2c83e4eb8b065622ade7`.
The retained environment includes the complete installed package resolution.

```sh
opam exec -- dune build --profile release coursework/bench/stm_framework.exe
mkdir -p .agents/runs/fresh-framework
for repeat in 1 2 3 4 5; do
  timeout 180 _build/default/coursework/bench/stm_framework.exe > .agents/runs/fresh-framework/framework-$repeat.json
done
```

All three backends use 8192 accounts and 100 checked Bank.total snapshots per
domain. Every snapshot must equal 8192000000. The framework owns synchronized
domain start, three warmups, five timed runs and randomized suite order. Five
complete passes preserve repeated backend comparisons. At one worker its
default extra untimed domain keeps the multicore runtime enabled. No custom
statistics engine or new dependency was introduced.

`framework-passes.csv` preserves all 90 native aggregate metric records from
five passes, nine backend/domain cases and two metrics. Every metric has five
runs and finite positive value/best/mean/median; SD is finite and nonnegative.
All nine expected cases appear exactly once per pass. `summary.csv` summarizes
the five pass medians. Its range is the range of pass medians, not the range of
all 25 inner timings: the framework does not emit individual inner timings.
No pass was removed. The native `ns` metric divides domain time by snapshots
per domain; the `M/s` metric is aggregate throughput across domains. Do not
invert the former as though it were global throughput at multiple domains.

The slowest baseline is TL2: aggregate medians 473.561, 806.092 and 1147.589
snapshots/s at 1/2/4 domains. Kcas gives 9144.920, 16396.450 and 18549.134;
Mutex gives 35835.666, 49309.774 and 40281.750. These are read-only synthetic
snapshots, not contended update, abort-rate, fairness or cache/NUMA evidence.
Kcas's 100-snapshot domain batches take roughly 11..22 ms, TL2 roughly
0.2..0.35 seconds, and Mutex roughly 2.7..10 ms. The short Mutex controls need
longer confirmation before precise performance conclusions. The framework run
does not collect CPU/RSS/GC deltas; those costs remain in the separate mixed
campaign and diagnostic evidence rather than being inferred here.
The original mixed baseline remains separately retained and incomplete at its
8192-account tier after a 900-second timeout.

`raw-sha256.txt` identifies every retained file in the hosted artifact,
including native JSON, stderr, environment, functional/negative receipts and
the pre-existing short mixed benchmark. Framework correctness is enforced by
the fixture's snapshot assertion and the successful process status; the
functional receipt alone cannot certify a metrics campaign.
