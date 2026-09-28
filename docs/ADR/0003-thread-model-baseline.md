# ADR 0003 — Baseline Ghostty's thread model before touching hot paths

## Context

Performance is miaotty's first product property. The fastest path is the one we
do not add to: `input → pty → vt → metal`. Badge updates, IPC, plugins and the
sidebar must never appear there. But we cannot honor that boundary without
knowing exactly which thread/queue does the PTY read, VT parse, render commit and
present in the forked Ghostty build.

## Decision

Before writing any code that touches terminal behavior:

1. **Document the upstream thread model** — enumerate the threads/queues of the
   forked build (PTY read, VT parse, render/commit, present, main) and the
   allowed contact points for our code (pane lifecycle events; a single coalesced
   main-thread apply point).
2. **Capture baselines** for every budget in `miaotty/bench/budgets.json`
   (frame time, key→glyph latency, throughput, cold start, memory) on the target
   machine.
3. **Wire CI gates** so a >5% regression on a hard budget fails the build.

## Consequences

- No hot-path work starts until steps 1–3 are done (this is a hard sequencing
  constraint, tracked as "P0" in the performance design).
- All additions are event-driven, coalescible, bounded, and disable-able; with
  every extra turned off, performance must be within noise of Ghostty.
- Anti-patterns are explicit: no I/O/locks/allocations on the hot path, no
  synchronous IPC, no polling timers, no per-frame scans, no unbounded queues.

## Status

Accepted. Step 1 (thread-model write-up) is **open** and blocks hot-path work;
its output supersedes this note with a concrete diagram and queue list.
