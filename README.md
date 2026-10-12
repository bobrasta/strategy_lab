# Strategy Lab

A desktop app for the [Hummer engine](/home/bob/projects/hummer-engine): build strategies, run backtests, replay them bar by bar, and compare runs, after MetaTrader 5's Strategy Tester with visual mode. It talks to `hummer serve` (JSON lines over stdio); every run and build is a child process of the service. The app only displays what the engine wrote.

## Install and start

```bash
./install.sh            # flutter build linux --release, then installs for this user:
                        #   ~/.local/share/strategy-lab/, the desktop entry and the icon
./install.sh --uninstall
```

Then start **Strategy Lab** from the application menu (or `gtk-launch strategy-lab`). The app starts the engine itself; the status pill in the top bar shows starting / ready / error and offers **Restart engine** and **Build engine** (`cmake --preset release && cmake --build --preset release`, output in the Build tab).

Development: `flutter run -d linux`. `--dart-define=SETTINGS_DIR=<dir>` keeps the settings elsewhere (tests use it).

## Using it

| Where | What |
|---|---|
| **Tester** (right) | Strategy (`strategies/*.cpp`, built / stale / not built) and **Build**; inputs form from `hummer inputs`; M1 data file; From/To (UTC, inclusive); the strategy's **protected period**; tick path, ambiguity rule, deposit, leverage; cost overrides (empty = the profile's value; zero-cost switch); **Start** with progress, **Stop**. |
| **Indicators** (right, top bar or rail; MT5 Navigator → Indicators) | The indicators in the engine's `indicators/*.cpp`, built / stale / not built, **Build** / **Rebuild** (compiler output in Results → Build) and **Add** (an indicator with an `.so`, built or stale). Add opens the inputs form (the Tester's, with the declared plots) → **Add to chart** computes it with the engine on the chart's data file (the open run's, or **Open chart** = the Tester's data file on its own), whole file, with progress. **On the chart**: every attached indicator (several, also of the same one) with show/hide, **Edit inputs** (recomputes; usually an engine cache hit), **Remove**, and on failure the error with the journal/stderr tails and **Retry**. An engine without indicator support shows "This engine has no indicator support" with **Build engine**; nothing else changes. |
| **Results** (bottom) | Backtest (the MT5-style report), Graph (balance, equity with its per-interval range, equity drawdown %; wheel or two-finger up/down zooms the time range at the pointer, sideways or drag pans, double-click or **Full range** resets), Trades, Deals, Journal, **History**, Build. Taller/shorter toggle. |
| **Chart** | Candles of the run's data file, cut at the run's end (or a data file on its own: empty chart → **Open chart**); M1/M5/M15/H1. Layers: trades (entry arrows, initial SL/TP, entry→exit line coloured by result), the strategy's drawings, optional FVG study zones (rail → Load events), and one layer per attached indicator: its plots as lines in their palette colour, style (solid/dashed) and width, broken at EMPTY_VALUE, and its zones/lines/markers drawn like strategy drawings (hover a marker or zone for its label). In Explore an indicator shows what was known at the chart's last bar; in Replay, at the cursor: for each bar the latest value stamped by then (a repainted bar changes when the cursor reaches the repaint). The rail's Layers list has each indicator with show/hide, Edit inputs and Remove. Click a trade on the chart or in Trades to select it. |
| **Replay** | Top bar → Replay, then click a bar, Jump to date, or **Replay trade** (50 bars before its entry). Space play/pause, ←/→ step, N or Shift+→ next trade event, 1–100 bars/s. The readout shows position, floating P&L, equity, balance and margin at the cursor, from the exact `equity.csv` row. |
| **History** | Every run in the engine's `runs/` with strategy, range, key inputs, trades, net profit, run time. Click to reopen (no re-run). Tick two and **Compare**: equity curves on one axis and all report fields side by side. |

**Protected periods.** Each strategy can have a hold-out (Tester → Data and dates → Edit); `fvg_continuation` defaults to 2024-01-01 onwards. A run overlapping it starts only after a confirmation dialog, logged with a timestamp in the run's folder (`protected_period_confirmation.json`). Overlapping runs that weren't confirmed show as **Protected** in History; their results stay hidden until you confirm them there (also logged).

**Settings** (strategy, inputs per strategy, dates, data file, model, account, costs, protected periods, last run or data-only chart, attached indicators with their inputs, visibility and order) are saved in `~/.local/share/com.example.strategy_lab/settings.json`. Parsed candles are cached in `~/.cache/com.example.strategy_lab/`. Attached indicators are recomputed at startup and whenever the chart's data file changes; the engine caches each output (`runs/indicators/<name>_<key>/`), so that is usually instant.

## Files

| Path | Role |
|---|---|
| `lib/engine/engine_service.dart` | `hummer serve` process: requests, events, protocol check, shutdown; engine freshness and Build engine |
| `lib/state/lab_state.dart` | Tester: strategies, builds, inputs, runs, history, protection, compare |
| `lib/state/app_state.dart` | Chart: series, view, replay cursor (`visibleCursor` / `nowMs`), selection |
| `lib/state/settings.dart` | Persisted settings |
| `lib/indicators/` | Indicators: list, builds, inputs form, attached instances and their engine jobs (`indicators_state.dart`); output folders parsed in an isolate into per-plot time-indexed records and a compact object index (`indicator_output.dart`) |
| `lib/run/` | Run files (`run_data.dart`), `equity.csv` index + random access (`equity_store.dart`), lookups at the cursor (`run_view.dart`), history scan, protected periods |
| `lib/data/` | Candle CSV parser and binary cache, resampling, FVG events (overlay) |
| `lib/chart/` | Chart painter and layers (`trades_layer.dart`, `drawings_layer.dart`, `fvg_layer.dart`, `indicator_layer.dart`) |
| `lib/widgets/` | Tester panel, Indicators panel, inputs form, results tabs, report, graph, history, compare, dialogs |
| `linux/packaging/`, `install.sh` | Desktop entry, icon, user install |

## Tests

```bash
flutter analyze && flutter test        # unit + widget tests; real-data / real-engine ones skip if missing
git config core.hooksPath .githooks   # once per clone: pre-commit runs scripts/check_repo.sh (no runs/, build/, data CSVs, equity files)
# Acceptance against the real engine (opens a window; runs fvg_continuation on 2021–2023 only):
flutter test integration_test/acceptance_test.dart -d linux --dart-define=SETTINGS_DIR=/tmp/sl-accept
flutter test integration_test/restart_test.dart    -d linux --dart-define=SETTINGS_DIR=/tmp/sl-accept
# M7 indicators (build, add, Explore, Replay, edit, remove, cache hit; then restart), in a new empty settings folder:
flutter test integration_test/indicators_test.dart         -d linux --dart-define=SETTINGS_DIR=/tmp/sl-ind
flutter test integration_test/indicators_restart_test.dart -d linux --dart-define=SETTINGS_DIR=/tmp/sl-ind
# M8 practice sessions (trade by hand in replay, pause; then restart, resume, finish), new empty settings folder:
flutter test integration_test/practice_test.dart         -d linux --dart-define=SETTINGS_DIR=/tmp/sl-practice
flutter test integration_test/practice_restart_test.dart -d linux --dart-define=SETTINGS_DIR=/tmp/sl-practice
# The volume profile tool (drag candle to candle → engine profile; resize; delete), new empty settings folder:
flutter test integration_test/volume_profile_tool_test.dart -d linux --dart-define=SETTINGS_DIR=/tmp/sl-vp
# UI-stall measurement + kill -9 of a worker, in profile mode (like the installed app):
flutter drive --profile -d linux --driver=test_driver/integration_test.dart \
  --target=integration_test/engine_test.dart --dart-define=SETTINGS_DIR=/tmp/sl-accept
```
