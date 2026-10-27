# Final candidate component confirmation

Production candidate: `cc3a7cfcdb04dc54054ec7446cc3d5f8d2cbe0f495c6c8367e7d2a89d8fabb7f`, version code 99, 3,901,562 bytes. All previous candidate `523bd07f` evidence remains independent and unchanged.

The first two runs on this candidate used the unchanged interaction probe (`0d5321e8f78dcd91cea69b9afa046a81a49f66d7bdff8ef85fc5db943e562787`) and passed 244/245 assertions. Their 150 ms screenshot delay captured some native window fade transition frames; these images are retained, not labeled as opaque final frames:

- `20261025-071043-font-1-0-943486`
- `20261025-071048-font-1-3-8c317e`

With root authorization, the probe then changed only screenshot settling to 500 ms and added read-only observations of the real window/decor background. It did not change production, disable animations, modify alpha, weaken text/back/outside/button assertions, or extend the business test scope. Final probe SHA256: `8450ab751dce5f6a0e55f0dbc9ad2760f49859f93745c7997e1111340ef5db47`.

Final runs, counted separately from superseded runs:

- `20261025-071234-font-1-0-814d64`: 244 assertions passed, 5 screenshots.
- `20261025-071241-font-1-3-1f5307`: 245 assertions passed, 5 screenshots.

All 10 final screenshots were individually viewed: rounded dialog corners are visible, the dialog body is opaque after native animation completion, and no background lettering bleeds through. The real decor observations report `clipToOutline=true`, background `GradientDrawable` alpha 255, background color `#FFFFFFFF` with color alpha 255, and view/window alpha 1. The component text and all action buttons remain readable; full notes reach the real scroll bottom at both font scales.

Final count is 489 repeated component assertions and 10 screenshots across two font configurations. Progress/error metadata are injected into the real manager fields and listener; these are component UI results, not backend delivery, actual download, unknown-source permission or installation integration results. MainActivity's implementation never runs, and the test host's page background/insets are not a whole-app layout approval. No phone or camera was used.

Preferences were restored in all runs. Each owned fixture was removed, the instrumentation package was uninstalled, and the installed production SHA was reverified. `emulator-5586` was left running and handed back to root. `COMPONENT-UI-RESULT.json` links every immutable report/provenance/cleanup file and distinguishes final runs from transition-frame runs.
