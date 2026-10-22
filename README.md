# OCaml transactional memory

This repository pairs the Kcas STM with a small experimental TL2 backend and a bank-transfer workload. It compares two optimistic transaction systems with an explicit mutex baseline on native OCaml 5 domains.

The upstream Kcas implementation, tests, documentation, and history remain intact. See [README.upstream.md](README.upstream.md) for the original guide. Kcas is an ISC-licensed multi-word compare-and-set STM. The source checkout is pinned at `7a83eb3d1900aeefde42a27c2af60e6d8b7b360e`, dated June 14, 2025. Its upstream update cadence is a known limitation of this base.

## Build and test

Use OCaml 5 and Dune from the repository's opam packages:

```sh
opam install . --deps-only --with-test
opam lock --keep-local .
opam install . --deps-only --with-test --locked
opam exec -- dune build @all
opam exec -- dune runtest
```

Run the real-domain check and keep its output:

```sh
opam exec -- dune exec coursework/bin/stm_verify.exe -- --doctor
opam exec -- dune exec coursework/bin/stm_verify.exe -- --evidence .agents/runs/local-1
```

The driver checks conservation under 1, 2, and 4 domains with Kcas, TL2, and Mutex. `dune runtest` adds same-cell increments, a barrier-controlled write-skew conflict, validation after commit-version reservation, prepublication failure cleanup, exception rollback, read-your-writes, progress after an aborted transaction, and a concurrent transfer history checked by a separate serial search. The negative control supplies an impossible transfer history and requires the serial checker to reject it.

The [native Ubuntu run](https://github.com/STEVVVU/ocaml-transactional-memory/actions/runs/39721462708) passed the upstream/coursework Dune suite, 5,250 real-domain transfers and the deliberate failure control. Its 135 interleaved benchmark summaries cover 315,000 recorded operation latencies with zero reported operation errors. [Retained verdicts and summaries](docs/evidence/linux-39721462708/) include the raw benchmark hash. These are bounded synthetic measurements, without a general speedup claim. The Windows workspace has no native OCaml toolchain.

## Experimental TL2 backend

`coursework/src/tl2.ml` implements integer cells with an atomic state containing either an unlocked value and version or a transaction lock owner. A transaction samples the global version, records a read set, stages writes, acquires write locks in cell-ID order, reserves a commit version, validates the read set, and publishes the staged values. It retries conflicts up to a caller-set bound, uses the existing randomized exponential `Backoff` library between failed attempts, and reports exhaustion as `Retry_limit`. Callers must handle exhaustion; backoff does not guarantee fairness or completion under arbitrary contention.

The fixed-width integer API keeps the write and read logs typed without `Obj.magic`. User transaction functions can run again after conflicts, so they must not perform I/O or other external side effects. Only mutations staged through `Tl2.write` join a transaction. This implementation is a teaching experiment. It does not replace Kcas, provide a formal proof of TL2, or claim lock-free progress, fairness, allocator safety, or general OCaml data support.

## Workload comparison

The benchmark runs disjoint, contended, and read-heavy bank operations through Kcas, TL2, and Mutex. It warms each workload, rotates backend order across five trials, keeps the operation schedule deterministic, and records each operation's latency plus summary counts using Mtime's monotonic OS clock. The CSV is evidence, not a speedup claim. Run it after creating an evidence directory:

```sh
opam exec -- dune exec --profile release coursework/bench/stm_bench.exe -- --output .agents/runs/local-1/bench.csv
```

## Longer native evidence

The original longer matrix [run 39728173211](https://github.com/STEVVVU/ocaml-transactional-memory/actions/runs/39728173211)
hit its 900-second limit in the 8192-account tier. Its completed rows are retained;
it is an incomplete campaign. TL2's completed one-domain read-heavy trials took
55.49..56.65 seconds for 20000 operations, with zero retries and about nine
billion allocated words per trial. No full-domain comparison is claimed from
that failed run.

The established `multicore-bench` 0.1.7 fixture then measured checked read-only
snapshots of the same 8192-account footprint in [run 39733269312](https://github.com/STEVVVU/ocaml-transactional-memory/actions/runs/39733269312).
Ubuntu 24.04, OCaml 5.3.0 Release and an AMD EPYC 9V45 VM reporting four logical
CPUs on two cores produced the following aggregate snapshots/second:

| Domains | Kcas | TL2 | Mutex |
| ---: | ---: | ---: | ---: |
| 1 | 9145 (8942..9509) | 474 (456..490) | 35836 (30581..36565) |
| 2 | 16396 (16104..16732) | 806 (767..874) | 49310 (34586..51862) |
| 4 | 18549 (17725..18624) | 1148 (1119..1181) | 40282 (38885..41311) |

Values are medians of five framework-pass medians, with the full range of pass
medians. Each pass randomizes suites and records five runs after three warmups,
with 100 checked snapshots per domain per run. Native JSON preserves each pass's
best/mean/median/SD/run count; individual inner timings are not emitted by this
framework. This read-only fixture supplements the mixed workload and is not a
transaction-abort or fairness measurement. Mutex's 100-snapshot batches are
short (roughly 2.7..10 ms per domain); treat those controls as provisional
until longer confirmation. Framework CPU/RSS/GC deltas were not collected.
[All 90 native aggregate metrics,
summaries, commands and raw hashes](docs/evidence/linux-39733269312/) are retained.

A [separate successful profile](docs/evidence/linux-39733272376/) confirmed
avoidable read-set sorting before TL2's read-only validation. Exclusive sorting
and comparator instructions account for 12.65% of its full diagnostic process,
which also includes all backends, setup and final correctness checks. This is
not a native wall-time percentage. Independent review approved a narrow
read-only validation fast path; native validation and the matched rerun remain
pending, so no improved performance result is claimed.

```sh
opam exec -- dune build --profile release coursework/bench/stm_framework.exe
mkdir -p .agents/runs/fresh-framework
for repeat in 1 2 3 4 5; do
  timeout 180 _build/default/coursework/bench/stm_framework.exe > .agents/runs/fresh-framework/framework-$repeat.json
done
```

The maintained fixture now uses 1000 snapshots per domain to lengthen the
Mutex controls. The workflow's `framework=true` comparison builds current
source and frozen `6ecf556`, overlays that identical maintained fixture onto
the archived baseline, and alternates five whole passes per build. It records
source/fixture/binary hashes, resources and exit receipts. This is an explicit
workload revision: the table above remains the original 100-snapshot baseline
and cannot be compared directly with a future 1000-snapshot result.

## Coursework and research

The workload follows the multicore transactional-memory topic in the [OCaml STM course project](https://vraajkum.github.io/ocaml-stm-webpage/). That project compares optimistic and pessimistic STM behavior on shared data structures. Its student implementation is not included here.

The separate TL2 implementation follows the mechanism described in Dice, Shalev, and Shavit, [Transactional Locking II](https://people.csail.mit.edu/shanir/publications/Transactional_Locking.pdf), DISC 2006. The paper's validation, versioning, and write-lock protocol guide the experiment. Bounded tests here do not reproduce the paper's full evaluation or establish its formal properties.

The inherited Windows workflow is archived byte-for-byte outside GitHub's active workflow directory; upstream scripts remain preserved. The added coursework workflow runs the upstream and coursework Dune tests on OCaml 5, captures package versions and lock files, exercises the driver, and preserves run evidence as an artifact.
