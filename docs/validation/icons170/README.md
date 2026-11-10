# 170 · Adjustment rail icon consistency

Local **0.30.16-beta /170** candidate; not uploaded or published.

调色盘、去灰、局部、修补 now use the same26dp bare AppIcon line-icon box,6dp top padding and shared caption baseline as exposure, contrast, curves and HSL. Local no longer has a separate circular ground. The shared circular39dp portrait variant stays intact. Labels, entry widths, callbacks, ripple/focus behavior and active tint logic are preserved. No image, selection or repair algorithms changed.

## Frozen artifacts

- Full APK: `dist/huevia-0.30.16-beta-debug.apk`; SHA256 `bb61358338530a4b4daeb2bff0938469c27b3e6acbe1043b822cd032006a4f43`;34,647,510bytes.
- Signed local delivery: `dist/upload170/huevia-0.30.16-beta-update.apk`; SHA256 `5814e69b63df75c265edf75ce197faaef67bcf4c3068651af2b73be8c1411805`;31,358,141bytes, below32MiB.

Only four obsolete x86 libraries were removed for the upload-size variant;88 retained payloads are byte-identical. ARM32/ARM64/x86_64 remain. Existing certificate, signaturev2/v3,16KiB alignment and backend offline APK inspection passed. Exact signed APK installed and cold-launched on the owned API36 emulator in1,557ms. This smoke covers startup only.

## Native verification boundary

The full source APK was installed by exact SHA on owned emulators. Four modes: phone/API37 1080×2424; narrow/font1.3/API36 840×1890; tablet/API36 1600×2560; landscape/dark/API37 2424×1080. Each has three actual native original PNGs (common rail, four tools, after tool-open/dismiss refresh),12 total. All nine measured entries in each mode have identical icon box, top padding and caption baseline, using AppIcon. All four actual tools opened/dismissed and model/history/source remained unchanged. Capture harness reports51 checks per mode, including inherited fixture/bootstrap checks; this is not204 new algorithm tests. Temporary capture-only automation is ignored under `.tooling`, repository tests unchanged.

Source, package, payload hashes, offline inspection, install smoke and capture geometry are recorded beside this file. Native layout/callback observations do not establish frame-rate, physical Samsung behavior, new full-export correctness or whole-app acceptance. No HTML/CSS detector ran on nativeJava and no production raster changed. Public-domain NASA portrait is QA only. Parent168/169 evidence and packages stay frozen.

One bounded self-inspection batch found no additional material visual gap. Independent fresh [finish review](../../../.impeccable/review/icons170/review.md) returned **ship**, no material fixes, scoped to icon consistency and direct regressions. The root design/product/surface records carry the same narrow170 boundary. Both emulator settings were restored and the owned API36 emulator closed; API37 stays available. No public OTA/upload/publishing was performed.
