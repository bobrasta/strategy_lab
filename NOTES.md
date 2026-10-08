# NOTES

## Done

- **Step 0.** Imported the FVG Lab design export (conditional-study version, `~/Downloads/New Folder (3)/flutter/fvg_lab`) into this project. Kept backy's `linux/` runner (1440×900, title "FVG Lab"), added `file_selector` + `path_provider`.
- **Python (fxdata, not a git repo; pre-edit copy kept outside fxdata).** `fvg_conditions.py` now also writes, on every non-`--control` run:
  - `fvg_events_app.csv`: every line of `fvg_events.csv` unchanged, plus `disp_q, trend, age_b, form_session, touch_session, sweep_b, period`, joined on (time, dir). It exits if the join or outcomes disagree.
  - `fvg_fake_events.csv` and `fvg_control_events.csv` (control = real + fake rows from the shuffled-bars run, `kind` column). Per-event files, so the app can apply any filter combination.
  - `fvg_conditions_summary.json`: per period (`in`, `out`, plus `holdout` only with `--holdout`) and bucket, it holds real/fake/control rates, n, diff_pp, z, context_pp, control_diff_pp, control_z and the verdict.
  - The control pass runs silently in-process (same seed). Its rows equal a real `--control` run's.
  - Printed tables are byte-identical for `--control`, default and `--confirm`. The only addition is a final "Saved …" line.
  - `max_wick` was added as a column of `fvg_condition_events*.csv`, needed for the fake-zone depth curve. No statistic changed.
  - `fvg_study.py` and `fvg_baseline.py` were not touched.
- **Steps 1–2.** Loading prefers `fvg_events_app.csv`, accepts the Python column names and validates `kind`. `fvg_conditions_summary.json` is cross-checked bucket by bucket on load, and a mismatch shows a notice. The last folder is remembered. The comparison card and verdict follow `fvg_conditions.py`.
- **Steps 3–5.** These were already correct in the design. The zone "outcome known" rule was extracted for testing. Tests cover the zone colour, counters, events table, autoscale, Predict, Next touch, 100 bars/s batching and the export fields.
- **Steps 6–7.** Tests cover bookmarks and resampling. The real M1 file resampled to M15 equals the M15 file on every sampled bar (Δ = 0).
- `--dart-define=CANDLES=… EVENTS=…` opens files at startup.
- Chart navigation: drag (time + price), two-finger touchpad up/down = zoom and left/right = scroll (axis locked per swipe, pinch zooms too), wheel = zoom, Shift+wheel = scroll, price-axis drag = candle height, double-click axis / Fit = autoscale. Tests in `test/chart_gestures_test.dart`.

## Verified

- `flutter analyze`: no issues. `flutter test`: 49 passing (real-data tests read `FXDATA_DIR`, skip if missing).
- Parity: 18,359 events · bounce 0.579 · P(bounce | d=0.5) 0.481 · in-sample Asia formation +3.39pp, candidate (control run +0.71pp). Every bucket in the JSON matches.
- Real app (`flutter run -d linux`, M1 and M15 files): everything loads, 0 unmatched events, replay ~100 bars/s.
- UI-isolate stalls in profile mode: M15 load 19 ms, M1 load 85 ms. Once at the end of events loading there's ~180 ms (first filter pass over ~170k real/fake/control events). Debug builds are 2–4× slower.

## Decisions

- Touchpad direction: fingers up = zoom in (like wheel up). If it feels inverted with your natural-scrolling setting, flip `_zoomPerPx` in `price_chart.dart`.
- Chart drag is limited to mouse/touch devices; touchpad two-finger gestures go to the Listener (Flutter's drag recognizer would otherwise claim them). `PointerPanZoomUpdateEvent.localPan` is offset by the widget's position, so the axis lock uses the global `pan`.

- Control semantics (user's choice): the control run's own real − fake, not a pooled "control" group. Candidate = real − fake z ≥ 2 and control z < 2; artifact = control z ≥ 2; min 30 resolved per group.
- 2024–25 out-of-sample is shown (user has run `--confirm`). The 2026 hold-out stays locked behind the design's reveal step.
- `fvg_baseline.py` JSON dropped (user's choice). The baseline JSON is still read if present, as a fallback for the faint curve.
- The stats drawer during replay shows full-sample stats, as in the design (they're study-level numbers, not tied to the cursor).
- `deprecated_member_use` is ignored in `analysis_options.yaml` (the design uses `Color.withOpacity` throughout).
- Geist isn't bundled, so the system falls back to Noto Sans, which is wider. The rail's two load pills use `FittedBox(scaleDown)` instead of overflowing by ~7 px.
- Tried and reverted (no effect on stalls): packing M1 time keys into one string, and sending only numeric columns to the resample isolate. The M1 stall comes from the parse isolate's allocations; isolates share one heap.

## Left / ideas

- If the 180 ms post-load stall matters: precompute per-event filter keys, or run the first `_applyFilters` incrementally.
- Bundle Geist (`assets/fonts/`) to match the design's typography.
- When 2026 data arrives: re-run `fvg_study.py` then `fvg_conditions.py`. The `period` column marks it `holdout`, and the app keeps it locked.
