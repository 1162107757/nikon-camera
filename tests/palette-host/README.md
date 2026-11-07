# Two-axis colour palette host checks

Run `./tests/palette-host/run-host.ps1` with PowerShell and JDK 17. Outputs stay in `.tooling/palette126/engine`.

The legacy golden was captured from the actual production engine **before** adding the palette, using `PaletteLegacyVectors`. It covers 294,912 synthetic packed ARGB outputs, advanced wire bytes, a v3 regional payload, a PED6 draft, and its identity. The runner compares the complete output with that immutable golden.

The new suite checks strict field/version limits and truncated data, independent manual/curves/HSL state, zero intensity and transparent pixels, tone monotonicity and endpoints, controlled warm-hue saturation, draft/recipe/rename/apply/copy/undo, old PED1–6 and PRC1–3 readers, invalid fields behind valid checksums, regional v4 data, mask-exterior exact pixels, normalized coordinates at two resolutions, and direct versus streamed rendering. Existing manual, colour, persistence and regional suites also run.

Only generated pixels and temporary test-owned files are used. Warm hue protection is a colour heuristic; these tests do not claim semantic skin detection or identical results to proprietary phone image pipelines.
