# NOTES

## Done

### M6 B: Strategy Lab (2026-10-10)
- **Rename** from FVG Lab: package `strategy_lab`, binary `strategy_lab`, app id `com.example.strategy_lab`, title "Strategy Lab". The FVG-study panels (stats, comparison card, events table, predict mode, bookmarks, drill-down, sample presets) are removed; the FVG zones stay as an optional overlay layer.
- **Engine service:** `EngineService` launches `hummer serve` from the engine repo (setting; default `/home/bob/projects/hummer-engine`, binary `build/release/hummer`), checks protocol 1, shows starting / ready / error. Build engine when the binary is missing or older than `engine/ cli/ sdk/ CMakeLists.txt`; Restart engine. Exit: `shutdown`, 2 s, SIGKILL.
- **Tester:** strategies with built / stale / not-built status (polled every 4 s, so an edited source shows stale and can be rebuilt without restarting), Build with streamed compiler output, inputs form from the schema (int/double/string fields, bool switch, timeframe and choice menus; values checked against min/max; only non-default values are sent), data file, dates, tick path, ambiguity, deposit, leverage, cost overrides, Start/Stop with progress. Failed runs show "Run failed" with signal or exit code and the journal/stderr tails.
- **Results:** report (all run.json summary fields), graph, trades, deals, journal, history, build log. Compare two runs.
- **Hold-out protection** (user requirement 1): per-strategy protected period in settings, `fvg_continuation` from 2024-01-01 by default; confirmation dialog before an overlapping run; `protected_period_confirmation.json` (UTC timestamp, period, kind start/reveal, run dates) in the run folder; unconfirmed overlapping runs are masked everywhere and need a logged reveal to open.
- **Run history** (2): scans `runs/*/run.json` in an isolate; reopen, replay, compare without re-running.
- **Large files** (3): `equity.csv` is scanned once in an isolate (8 MB chunks) into a 512-row block index and ~3,000 graph buckets; replay reads the ~50 KB block around the cursor (LRU of 8). Candles (2M M1 rows) are parsed byte-level in an isolate and cached as a binary file; all chart timeframes are resampled in the same isolate (nothing large is copied between isolates).
- **Settings persistence** (4): `settings.json` in the app support folder, debounced atomic writes.
- **Engine change** for rule "nothing recomputed in Dart": `equity.csv` gained `profit` (equity − balance), `drawdown` and `drawdown_pct` (deepest tick-level drawdown in the interval); see the engine's NOTES.
- **Graph time zoom:** wheel / two-finger up/down zooms at the pointer, sideways or drag pans, double-click or **Full range** resets (the price chart's gestures). The y-axis autoscales to the window; time labels go from years down to hours. A zoomed window is re-bucketed from just its blocks of `equity.csv` in an isolate (`EquityStore.bucketsIn`, ~1 bucket per pixel, window ± 25% so small pans reuse it); the whole-run buckets show until it arrives. Replay's cut applies to window buckets too.
- **Geist bundled:** v1.7.2 from the vercel/geist-font release (Light/Regular/Medium/SemiBold/Bold, SIL OFL in `assets/fonts/OFL.txt`). Widget tests now measure with it (`loadAppFont`).
- **Repo hygiene:** `scripts/check_repo.sh` (same as the engine's) as the pre-commit hook (`git config core.hooksPath .githooks`) and in `flutter test`; `.gitignore` ignores `build/`, `runs/` and `*.csv`.
- **Desktop entry:** `linux/packaging/strategy-lab.desktop` + `.svg` icon; `install.sh` (and `--uninstall`).

## Verified

- `flutter analyze`: no issues. `flutter test`: 62 passing (graph zoom: window buckets vs the rows, isolate bucketing, window points under a replay cut, time ticks, wheel/double-click/Full range; fast parsers bit-identical to `double.parse` on 200k values; equity store vs a linear scan across block boundaries; replay rules bar by bar on a hand-made run; protected periods; settings round-trip; app = CLI trades from a real engine run; widgets at 1440×900 and 1920×1037).
- Acceptance against the real engine (`integration_test/`): build fvg_continuation, run 2021-01-01..2023-12-31, open, replay a trade; To = 2024-03-31 → Start shows the protected-period dialog, Cancel starts nothing; restart (new process, same settings) → settings remembered, the run reopens from History and replays; `pgrep hummer` empty after each.
- `kill -9` of a worker mid-run → "Run failed · SIGKILL", the next run works. `kill -9` of the app → the service exits (parent-death signal). Window close → `shutdown` logged, no processes left.
- Installed with `install.sh`, launched through the desktop entry (`gtk-launch strategy-lab`): engine starts.

## Measured (release / profile, Ryzen 7 PRO 5850U)

| What | Result |
|---|---|
| Parse the 2,044,519-row M1 CSV (isolate, AOT) | 3.2 s first time; from the binary cache afterwards |
| Scan the full-data per-M1 `equity.csv` (2,045,853 rows, 288 MB) | 3.1 s (isolate) |
| Equity row at the cursor (block read + parse) | ~2 ms on a cache miss |
| Full ma_cross run 2021–2026 + open, profile mode | 9.2 s; worst UI event-loop gap **65 ms** |
| Graph zoom re-bucket (275 MB file, isolate, JIT; window ± 25%) | 1 week 44 ms · 1 month 84 ms · 1 year 1.1 s |

## Decisions

- Results drawer at the bottom (MT5 tester tabs), Tester settings in the right drawer, both overlaying the chart as the FVG Lab drawers did.
- The trades layer draws the **initial** SL/TP: later modifications are only known from `sl_final`/`tp_final` at the exit, so drawing them earlier would leak the future.
- Report fields that MT5 shows as percentages but the engine doesn't write (long/short won %) are shown as counts. Compare has no difference column.
- Graph buckets are min/max picks of rows parsed to plotting precision; every number shown as text (hover, readouts) is an exact row read with `double.parse`-identical parsing.
- A confirmation covers only the period it was made for; changing a strategy's protected period asks again. Weakening or removing a protection asks once more.
- History reads `runs/` directly (not `list_runs`), so it works while the engine is down.
- Chart candles stop at the run's last simulated bar; bars after the run are never shown with it.
- Integration tests run in debug mode, where JIT warm-up adds UI pauses; the stall budget is checked in profile mode (`flutter drive --profile`).

## Left / ideas

- A per-deal x-axis on the graph, like MT5's.
