# Performance

Budgets live in `budgets.json` (see `docs/ARCHITECTURE.md` §3).
Anything we add must stay off the `input → pty → vt → metal` hot path.

## Entry points

- `bench/run.sh` — IPC/idle smoke + budget dump.
- Once the fork is bootstrapped: vtebench, Ghostty's benchmark suite, and
  Instruments (Time Profiler / Metal System Trace) traces feed the same budgets.

## Gates

- Any PR touching a hot path must include before/after numbers.
- >5% regression on a hard budget fails CI.
- "All extras disabled ⇒ performance within noise of Ghostty" is a release gate.
