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
flutter run -d linux \
  --dart-define=CANDLES=/home/bob/Documents/fxdata/xauusd_m15_2021-01-01_2026-01-01.csv \
  --dart-define=EVENTS=/home/bob/Documents/fxdata/fvg_events.csv   # open files at startup
flutter test                                  # real-data tests read FXDATA_DIR (default ~/Documents/fxdata), skip if absent
```

Window size: in `linux/runner/my_application.cc` set
`gtk_window_set_default_size(window, 1440, 900);` (plus min-size geometry hints if you like).

Font: put the Geist TTFs in `assets/fonts/` and uncomment `fonts:` in `pubspec.yaml`.

## Files the app reads

| File | How |
|---|---|
| Candles CSV `time,open,high,low,close,volume` (UTC) | Load candles. Any timeframe; M1 enables resampling and drill-down |
| `fvg_events.csv` | Load events. One row per first touch, times matched to candles **by exact string**. If `fvg_events_app.csv` sits next to it, that is loaded instead |
| `fvg_events_app.csv` | `fvg_events.csv` + `disp_q, trend, age_b, form_session, touch_session, sweep_b, period` (from `fvg_conditions.py`) |
| `fvg_fake_events.csv` | Auto-loaded. Size-matched fake zones (`fvg_conditions.py`), same condition columns |
| `fvg_control_events.csv` | Auto-loaded. The shuffled-bars control run, real and fake rows (`kind`) |
| `fvg_conditions_summary.json` | Auto-loaded. The study's own per-bucket table; the app cross-checks its numbers against it on load |
| `fvg_baseline_summary.json` | Optional fallback for the faint fake-zone curve when there's no fake events file |
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

## Zones and labels

- Non-selected zones are drawn at ~35% strength; the selected one (or the pending call in Predict) at full.
- Labels show only on the selected zone and the one under the mouse: `Bounce · wick 0.44`, `Break · wick 3.25`
  (wick = the study's max_wick once resolved), `Open · wick 0.31` (running, bars ≤ cursor) or `Waiting`.
  The **Labels** toggle shows them on every zone.
- **Selected only** hides every other zone (with nothing selected, all zones show so you can pick one).
- The condition filters (Displacement, Formation/Touch session, HTF trend, Age, Sweep, Period) are in the
  top bar's **Filters** popover; the badge counts the active ones.
- "Where clean bounces turned" counts only `bounce_inside_gap` events (max_wick < 1), with fvg_study.py's
  bins: `pd.cut(max_wick, np.arange(0, 1.01, 0.1), include_lowest=True)`.

## Chart navigation

- **Drag** the chart: left/right scrolls through time, up/down moves the price view.
- **Two fingers on the touchpad**: up/down zooms (around the pointer), left/right scrolls. Each swipe locks
  to its main direction, so a sideways swipe never zooms. Pinch also zooms.
- **Mouse wheel** zooms around the pointer; **Shift + wheel** scrolls.
- **Drag the price axis** up/down to make candles taller/shorter. **Double-click** the axis (or Fit) to go
  back to autoscale. The manual scale stretches the autoscaled range, which is still built from bars ≤ the
  replay cursor only, so it can't reveal the future.
- Gestures stop zooming out at 5,000 bars (Fit still shows everything). Directions can be flipped with the
  constants at the top of `_PriceChartState` in `lib/chart/price_chart.dart`.

## Timeframes

With an M1 file loaded, M1/M5/M15/H1 are resampled in an isolate and cached. Events stay on the
timeframe they were matched to (auto-detected: M15, then M5, H1, M1); zones are drawn only on that
timeframe, except **View on M1** drill-down, which maps the selected event to M1 bars and shows
the events-timeframe candle boundaries.

## Conditional study

Optional events columns (filters turn off if absent): `disp_q` (D1 weak … D4 strong),
`form_session`/`formation_session`/`session`, `touch_session` (derived from touch hour if missing),
`trend`/`htf_trend` (aligned/against), `sweep_b`/`sweep` (after sweep/no sweep, yes/no). Age buckets come
from `age`; Period from the `period` column, else formation year (2021–23 in-sample, 2024–25
out-of-sample, 2026 hold-out).

**Real vs fake vs control** card: bounce rates (timeouts excluded) of real and fake events under the
active filter and period, and the control run's own real − fake (same procedure on shuffled bars), with
pooled two-proportion z, exactly as `fvg_conditions.py`. Verdict: *Candidate* = real beats fake (z ≥ 2)
and the control run doesn't (z < 2); *Artifact* = the control run shows it too (z ≥ 2); *No edge* = real
doesn't beat fake; needs ≥ 30 resolved per group. Any bucket in `fvg_conditions_summary.json` that the
app computes differently raises a notice (files from different runs).

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
