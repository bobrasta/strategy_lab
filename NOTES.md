# NOTES

## Done

- Step 0: imported the FVG Lab design export (`~/Downloads/New Folder (3)/flutter/fvg_lab`, conditional-study version) into this project, kept backy's `linux/` runner (window 1440×900, title "FVG Lab"), added `file_selector` + `path_provider`. `flutter analyze` clean; app launches with `--dart-define=PRESET=3`.

## Left

- Python outputs for the conditional study (fvg_conditions.py), then Flutter steps 1–7 with tests, parity test, real-file run.

## Decisions

- `deprecated_member_use` is ignored in `analysis_options.yaml` (the design uses `Color.withOpacity` throughout; as in the export's own config).
- Geist isn't bundled, so the system falls back to Noto Sans, which is wider. The two "Load candles / Load events" pills in the expanded rail overflowed by ~7 px; they're wrapped in `FittedBox(scaleDown)` so they shrink ~5% instead of overflowing. No visual change once Geist is installed.
- The design export's "old" folder (`~/Downloads/flutter/fvg_lab`) was overwritten by the same new version; both are identical.
