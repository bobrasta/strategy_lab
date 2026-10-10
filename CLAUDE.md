# Strategy Lab

Flutter Linux desktop app for the Hummer backtesting engine: runs backtests through `hummer serve`, replays them, compares runs. It grew out of FVG Lab (`/home/bob/flutter_projects/backy`, reference only, never modify it).

## Folders

- App: `/home/bob/flutter_projects/strategy_lab` (this repo).
- Engine: `/home/bob/projects/hummer-engine`. Its `CLAUDE.md` and `SPEC.md` (§8.2 service, §14 M6) apply. Runs are written to its `runs/` (git-ignored).
- Market data: `/home/bob/Documents/fxdata` (read-only). Never copy the large CSVs into this repo; tests read them from `FXDATA_DIR` (default `/home/bob/Documents/fxdata`) and skip when missing. Real-engine tests use `HUMMER_REPO` (default the engine path) and skip without its binary.

## Hard rules

1. **Engine computes, app displays.** Every number shown comes from engine output files (`run.json`, `trades.json`, `deals.csv`, `equity.csv`, `drawings.jsonl`, `journal.txt`). Nothing is recomputed in Dart: no differences, ratios or percentages the engine didn't write. Rounding for display is fine.
2. **No lookahead in replay.** `AppState.visibleCursor` is the only "now"; `AppState.nowMs` is its last instant (the cursor bar's last tick). Nothing stamped after it is drawn, listed or read: candles, trades (exit only once reached), drawings (state as of now), equity readouts and graph, tables, journal, price autoscale. The full-run report is hidden during replay.
3. **Protected periods.** Per-strategy hold-out dates in the settings (default: `fvg_continuation` from 2024-01-01). Starting an overlapping run needs the confirmation dialog, which is logged with a timestamp in the run's folder (`protected_period_confirmation.json`). Results of overlapping runs are never shown (history, reports, compare, chart) unless that run was confirmed for that same period.
4. **FVG continuation:** run it only on 2021-01-01 .. 2023-12-31 unless the user asks, never tune its defaults, and never summarise its results (P&L, win rates, R) unless the user asks. Tests check only that a run exists and has trades.
5. **No process outlives the app.** The app owns `hummer serve`: `shutdown`, 2 s, then kill. Never run engine code in-process.
6. Keep the existing visual design (`lib/theme.dart`, the pill/glass widgets in `lib/widgets/common.dart`) and the `ChartLayer` architecture.
7. The UI isolate never blocks on big files: candles, equity and run files load in isolates (the 2M-row M1 data and the ~290 MB per-M1 `equity.csv` included).

## Working style

- Commit after each step with a clear message; ask when the spec conflicts with code or is ambiguous.
- Keep `NOTES.md` current (done / left / decisions).
- Verify with `flutter analyze` (no issues) and `flutter test`. The acceptance runs against the real engine are in `integration_test/` (see README).
