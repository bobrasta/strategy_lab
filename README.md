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
| **Results** (bottom) | Backtest (the MT5-style report), Graph (balance, equity with its per-interval range, equity drawdown %), Trades, Deals, Journal, **History**, Build. Taller/shorter toggle. |
| **Chart** | Candles of the run's data file, cut at the run's end; M1/M5/M15/H1. Layers: trades (entry arrows, initial SL/TP, entry→exit line coloured by result), the strategy's drawings, optional FVG study zones (rail → Load events). Click a trade on the chart or in Trades to select it. |
| **Replay** | Top bar → Replay, then click a bar, Jump to date, or **Replay trade** (50 bars before its entry). Space play/pause, ←/→ step, N or Shift+→ next trade event, 1–100 bars/s. The readout shows position, floating P&L, equity, balance and margin at the cursor, from the exact `equity.csv` row. |
| **History** | Every run in the engine's `runs/` with strategy, range, key inputs, trades, net profit, run time. Click to reopen (no re-run). Tick two and **Compare**: equity curves on one axis and all report fields side by side. |

**Protected periods.** Each strategy can have a hold-out (Tester → Data and dates → Edit); `fvg_continuation` defaults to 2024-01-01 onwards. A run overlapping it starts only after a confirmation dialog, logged with a timestamp in the run's folder (`protected_period_confirmation.json`). Overlapping runs that weren't confirmed show as **Protected** in History; their results stay hidden until you confirm them there (also logged).

**Settings** (strategy, inputs per strategy, dates, data file, model, account, costs, protected periods, last run) are saved in `~/.local/share/com.example.strategy_lab/settings.json`. Parsed candles are cached in `~/.cache/com.example.strategy_lab/`.

## Files

| Path | Role |
|---|---|
| `lib/engine/engine_service.dart` | `hummer serve` process: requests, events, protocol check, shutdown; engine freshness and Build engine |
| `lib/state/lab_state.dart` | Tester: strategies, builds, inputs, runs, history, protection, compare |
| `lib/state/app_state.dart` | Chart: series, view, replay cursor (`visibleCursor` / `nowMs`), selection |
| `lib/state/settings.dart` | Persisted settings |
| `lib/run/` | Run files (`run_data.dart`), `equity.csv` index + random access (`equity_store.dart`), lookups at the cursor (`run_view.dart`), history scan, protected periods |
| `lib/data/` | Candle CSV parser and binary cache, resampling, FVG events (overlay) |
| `lib/chart/` | Chart painter and layers (`trades_layer.dart`, `drawings_layer.dart`, `fvg_layer.dart`) |
| `lib/widgets/` | Tester panel, results tabs, report, graph, history, compare, dialogs |
| `linux/packaging/`, `install.sh` | Desktop entry, icon, user install |

## Tests

```bash
flutter analyze && flutter test        # unit + widget tests; real-data / real-engine ones skip if missing
# Acceptance against the real engine (opens a window; runs fvg_continuation on 2021–2023 only):
flutter test integration_test/acceptance_test.dart -d linux --dart-define=SETTINGS_DIR=/tmp/sl-accept
flutter test integration_test/restart_test.dart    -d linux --dart-define=SETTINGS_DIR=/tmp/sl-accept
# UI-stall measurement + kill -9 of a worker, in profile mode (like the installed app):
flutter drive --profile -d linux --driver=test_driver/integration_test.dart \
  --target=integration_test/engine_test.dart --dart-define=SETTINGS_DIR=/tmp/sl-accept
```
