# FVG Lab (backy)

Flutter Linux desktop viewer and replay tool for the Python FVG study.

## Folders

- App: `/home/bob/flutter_projects/backy` (this repo).
- Research data + Python: `/home/bob/Documents/fxdata` (not a git repo).
  - `fvg_study.py` produces `fvg_events.csv`; `fvg_conditions.py` adds the conditional study; `fvg_baseline.py` real vs fake gaps.
  - `index.py` is the Dukascopy downloader: don't touch.
  - Candles: `xauusd_m15_2021-01-01_2026-01-01.csv`, `xauusd_m1_2021-01-01_2026-01-01.csv` (UTC, `YYYY-MM-DD HH:MM:SS`).
- Never write app code into fxdata. Never copy the large CSVs into this project: the app loads them at runtime via file dialogs, tests reference them by absolute path (`FXDATA_DIR`, default `/home/bob/Documents/fxdata`) and skip with a message when missing.

## Hard rules

1. Python is the single source of truth. The app never detects FVGs or computes outcomes. It only aggregates the per-event outcomes the study wrote. `lib/demo/demo_events.dart` is the only Dart gap detector and exists solely for the bundled sample presets (`--dart-define=PRESET=1..4`); it must never run on loaded files.
2. No lookahead. `AppState.visibleCursor` is the only "now". Nothing right of it may be drawn or used: candles, zones, outcome colours, price autoscale, OHLC readout, counters, tables, Predict mode (the pending touch bar shows its open only until the call is made).
3. Keep the existing visual design, theme (`lib/theme.dart`) and the `ChartLayer` architecture. Don't restyle unless the spec asks.
4. Don't modify the core logic of `measure()` / `label()` in `fvg_study.py`, or the statistics / `--confirm` / `--control` behaviour of `fvg_conditions.py`. Only add outputs, and verify printed tables are unchanged after edits.

## Parity targets (from fvg_events.csv, no filters)

18,359 first touches · bounce rate 0.579 excluding timeouts · P(bounce | d=0.5) = 0.481 · in-sample Asia-formation real−fake diff +3.4pp.

## Working style

- Commit after each step with a clear message; ask when the spec conflicts with code or is ambiguous.
- Keep `NOTES.md` current (done / left / decisions).
- Python: no `~/fvg-env`; system `python3` has pandas 2.2.3.
- Verify with `flutter analyze` (no issues) and `flutter test`.
