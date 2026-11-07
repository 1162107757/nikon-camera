# Automatic exposed-skin tones — 118 / 0.23.7-beta

This revision corrects 117's face-dependent skin-tone workflow. Entering the
skin-tone tool automatically identifies exposed skin across the image. The user
chooses colour and strength; selecting a face or switching a body scope is not
required. A photo with no detected face can still use the feature.

`PhotoExposedSkin` runs the bundled semantic model on the whole image and combines
body-skin and face-skin classes. It retains disconnected skin regions and does
not assign them through face seeds. Optional local face landmarks refine eye,
brow, lip and nostril protection; their absence or refinement failure does not
reject the semantic skin result. The helper never adds faces to the edit model.

Version-4 portrait data stores the full-image mask and global tone independently
of face edits. It reads v1–v3 data. Global and individual face colour modes are
mutually exclusive, while existing face brightness/texture/light edits remain
available. A global reference colour is sampled from masked source skin once per
render, preserving local light/shadow and colour variation. Original and zero
strength leave image pixels unchanged.

All original colour presets, custom selection, photo sampling, preview transaction
and personal swatches remain available without a selected face. Private photo
fixtures, crops and image-derived diagnostics are excluded from the package and
this directory.

The retained APK is `dist/huevia-0.23.7-beta-debug.apk`, 33,403,660 bytes,
SHA-256 `879a214ba0fe85f991e8792e4f1683380df4c8c74fd9ac9141602ad5af24e920`.
`BUILD-IDENTITY.json` freezes 288 production inputs; `PACKAGING-AUDIT.json` verifies
the version, signer, v2/v3 signature, native alignment, new fields/classes and
unchanged model/native/notices. `HOST-RESULT.json` records 1,184 passing tests,
including independent v1–v3 compatibility, no-face global render/drafts/profile
export, alpha, mask-zero background, skin reference sampling and all EXIF directions.

`NATIVE-SUMMARY.json` links the final APK's focused correction checks: 440 phone,
440 font 1.3 and 459 landscape assertions, all passing, with 18 screenshots. The
actual NONE portrait has an empty face list throughout automatic recognition,
colour controls, custom preview, history, draft restoration and full/detail export.
Both subjects receive skin colour while mask-zero background remains unchanged.

`LOCAL-SKIN-QUALITY.json` contains two offline, metrics-only reproductions. The
full scene recognizes face and contacting fingers without creating face records.
An independent hand/wrist-only crop has zero actual detector faces, yet 9,602
nonzero mask cells and weight 1 at finger, palm and wrist samples. Clothing and
background samples remain zero. No private source paths, coordinates or image
pixels are included. This bounded check is not a population accuracy benchmark.

`VALIDATION-RESULT.json` and `FINAL-STATUS.json` record the completed local package.
Private remote fixtures and test packages were removed, preferences and device
settings restored, and the owned emulator was closed after verification.

The user requested retaining installation packages locally and resuming upload
manually. This revision does not upload a release or schedule an automatic run.
