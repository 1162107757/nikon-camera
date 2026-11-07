# Original NCP batch native regression

Reflection-only instrumentation for the 149 originals in
`.tooling/nikonpc-import-20261027/ready-manifest.json`. The probe APK packages the
unchanged files, SHA audit and independently frozen monochrome vectors. It contains
no production preview class. Run only against the explicitly handed-off emulator
and exact frozen candidate APK. No camera, user image, network or publishing step.

The first phone batch covers every original through Android profile dispatch and
the real 320px `PresetPreviewRenderer`, all19 monochromes against fixed independent
pixel vectors plus exact 0/50/100 completed-effect mixing. Native UI cases exercise
old122 error keys beside new-model success keys on the same library record, ready
native picker cards, editor card clicks, two independent synthetic-photo drafts,
and monochrome/color full/detail export at representative EXIF1/6. The renderer
uses the built-in synthetic template; its exact preference key is restored.
One separately named owned record is temporarily moved away after the editor has
loaded its library, then restored at the same path/SHA before a real retry click.
Its error must be retryable and must recover without importing a new record.
A separate structurally valid, unverified-toning fixture must remain explicitly
unsupported and nonretryable, with no selection/history change when tapped.
Existing preset bytes/metadata are preserved; newly imported test records, photos,
drafts and render surfaces are removed. The runner restores device settings and
uninstalls only `cc.huevia.ncpqa`. Evidence is kept with candidate/probe/input hashes.

Frozen vector schema supplied by the model/reference audit:

```json
{"modelVersion":"...","argb":["ffff0000","ff00ff00"],"outputs":{"original-file-sha256":{"argb":["...","..."]}}}
```

Use more than eight input pixels, including neutral and color patches, dark/light
values and varied alpha. Each of the19 original mono SHA values must be present.

Build only after the final coefficients/vectors are frozen and production build
coordination permits:

```powershell
./tests/ncp-preview-device-probe/build.ps1 -GoldenFile <absolute-frozen-vectors-path>
./tests/ncp-preview-device-probe/run.ps1 -CandidateApk <candidate> -ExpectedApkSha256 <sha> -Serial emulator-5588 -Mode phone
```

`-Scope full` runs the149/model matrix and the full UI/export workflow.
`-Scope core` continues the full UI/export workflow using representatives and the
painted-region integration, without repeating an already completed149 matrix.
Use that only when the earlier numerical phase is separately retained and source
freeze proves all profiles, renderer and golden unchanged across a UI-only fix.
`-Scope ui` is the short font1.3/landscape representative route and omits the
unchanged numerical matrix, controlled fault cases and full/detail export.
Every report records its actual scope. Historical failed-run check counts are
kept separately from successful final-candidate totals.

Preparation can independently validate Java17/D8 and every original SHA without
inventing a golden file or creating an installable APK:

```powershell
./tests/ncp-preview-device-probe/build.ps1 -CompileOnly
```

The old failure-cache prefix is independently bound to the exact NUL-terminated
model-version string found in the sealed122 APK DEX (SHA `a8c765ec…`); it is not
inferred by removing an arbitrary suffix from the new model key.

This tests app preview consistency and audited NX reference behavior; it does not
claim a recovered Nikon camera pipeline or all-camera rendering equivalence.
