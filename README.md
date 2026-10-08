# FVG Lab (Flutter · Linux desktop)

Chart, replay and research UI for the FVG study. **The Python study is the single
source of truth**: outcomes, depths, scenarios and baseline come from its output
files. The app never detects gaps or computes outcomes for loaded data.

## Run

```bash
cd fvg_lab
flutter create --platforms=linux .     # generates linux/ runner once
flutter pub get
flutter run -d linux                   # opens empty: load your files
flutter run -d linux --dart-define=PRESET=3   # demo on bundled sample: 1 explore · 2 drawers · 3 replay · 4 predict
```

Window size: in `linux/runner/my_application.cc` set
`gtk_window_set_default_size(window, 1440, 900);` (plus min-size geometry hints if you like).

Font: put the Geist TTFs in `assets/fonts/` and uncomment `fonts:` in `pubspec.yaml`.

## Files the app reads

| File | How |
|---|---|
| Candles CSV `time,open,high,low,close,volume` (UTC) | Load candles. Any timeframe; M1 enables resampling and drill-down |
| `fvg_events.csv` | Load events. One row per first touch, times matched to candles **by exact string** |
| `fvg_baseline_summary.json` | Auto-loaded from the events folder if present (faint curve fallback) |
| `fvg_fake_events.csv`, `fvg_control_events.csv` | Auto-loaded from the events folder. Need `time,dir,outcome`; condition columns let the same filters apply |
| `fvg_holdout.json` | Written when you reveal the 2026 hold-out (date + filters at reveal) |
| `fvg_bookmarks.json` | Auto-loaded/saved next to the events file (stars + notes, key `time|dir`) |

Parsing runs in an isolate (`Isolate.run`). Errors are shown in a banner: wrong file type,
missing columns, unordered times, and how many events aren't found in the candle file.

## What's computed where

- **Stats** (`data/stats.dart`): only from loaded events after filters. Timeouts are excluded
  from bounce/break denominators. P(bounce | d) = share of `bounce` among non-timeout events with
  `max_wick ≥ d`, d = 0.0…1.3, hidden where n < 20.
- **Baseline card / faint curve**: straight from `fvg_baseline_summary.json` (`diff_pp`, `z`;
  |z| ≥ 3 significant, ≥ 2 weak). When Direction and Gap size are both filtered and `by_size`
  has that row, that row is used. No file → "No baseline loaded".
- **Zones**: built from `edge`, `far`, formation/touch/end indices. Only the running max-depth
  line during replay is measured in Dart, from bars ≤ cursor. K and fail buffer in the rail are
  display-only (defaults 1.0 / 0.25).
- `lib/demo/demo_events.dart` is a **demo-only** generator for the bundled sample presets. It is
  never used for loaded files.

## No lookahead

`AppState.visibleCursor` is the only "now"; every layer gets it via `LayerContext.cursor`.

- zones appear when `formed ≤ cursor`, extend to `min(cursor, end)`, stay grey until `cursor ≥ end`
- autoscale, OHLC readout, counters and the events table (in replay) use bars ≤ cursor only
- **Predict**: when the next bar is an unpredicted first touch, playback stops on the bar before it;
  that bar is drawn as an open tick only (`AppState.peek`). The candle is revealed after you answer.
  Touch-bar resolutions are predicted the same way.

## Replay

Speeds 1–100 bars/s. A 16 ms timer advances however many bars are due, so the chart repaints
at most ~60×/s. Keys: Space play/pause · ←/→ step · **N** next touch (stops just before it) ·
Shift+→ next formation/touch/resolution · F focus · Esc cancel / leave M1 drill-down.

Predictions persist for the session across replay restarts; export via the overlay
(CSV: formation_time, dir, scenario, session, size_q, call, actual, correct, answered_at).

## Timeframes

With an M1 file loaded, M1/M5/M15/H1 are resampled in an isolate and cached. Events stay on the
timeframe they were matched to (auto-detected: M15, then M5, H1, M1); zones are drawn only on that
timeframe, except **View on M1** drill-down, which maps the selected event to M1 bars and shows
the events-timeframe candle boundaries.

## Conditional study

Optional `fvg_events.csv` columns (filters turn off if absent): `disp_q` (D1 weak … D4 strong),
`formation_session`/`session`, `touch_session` (derived from touch hour if missing), `htf_trend`
(aligned/against), `sweep` (yes/no). Age buckets come from `age`; Period from formation year
(2021–23 in-sample, 2024–25 out-of-sample, 2026 hold-out).

**Real vs fake vs control** card: bounce rates (timeouts excluded) of real, fake and control events
under the active filter and period, with pooled two-proportion z. Verdict: *Candidate* = real beats fake
and control (z ≥ 2 each); *Artifact* = real beats fake but |z| < 2 vs control; *No edge* otherwise; needs
≥ 30 resolved per group.

**Hold-out** is locked by default: excluded from all stats and hidden in Explore (chart, table, detail).
Replay can still play hold-out bars. "Reveal hold-out" asks first and writes `fvg_holdout.json`.

Presets menu: "Asia formation (candidate)" (Formation session = Asia), "Clear all filters".
Predictions export adds disp_q, formation/touch session, htf_trend, age_bucket, sweep, period.

## Structure

```
lib/
  main.dart                keyboard
  theme.dart               palette, text, icons
  data/
    candles.dart           columnar OHLCV + exact time keys
    loaders.dart           CSV parsing for candles + events (isolate), LoadError
    resample.dart          M1 → higher timeframes (isolate)
    events.dart            FvgEvent, scenarios, sessions, mapping, Zone, runningDepth
    stats.dart             stats from events
    baseline.dart          fvg_baseline_summary.json
    bookmarks.dart         fvg_bookmarks.json
    predictions.dart       prediction records + CSV
    sample_data.dart       demo candles
  demo/demo_events.dart    DEMO ONLY event generator for presets
  state/app_state.dart     ChangeNotifier: loading, filters, replay clock, predict, drill-down
  chart/                   geometry, ChartLayer registry, FVG layer, painter
  widgets/ screens/        UI
```
