# Painted adjustment regions

Run `./run.ps1` with JDK 17. The suite compiles the real immutable models, shared renderers and draft store and runs under a 96 MiB heap. It uses synthetic pixels only.

The matrix checks all 17 ordinary adjustment parameters plus curves and HSL at all eight EXIF orientations. An independent exhaustive capsule/feather oracle checks the indexed brush and every final composite against a complete, unmasked invocation of the existing effect. The clarity fixture is large enough for its scaled spatial bands to have different radii. Zero brush coverage preserves packed ARGB exactly, including hidden RGB at alpha zero. Feather and region strength are applied once after the full effect pipeline.

Other checks cover ordered paint/erase, short-side radius on non-square images, independent region state and order, ordinary effects alongside semantic skin edits, whole exposed-skin texture and face light, original/zero/disabled/unpainted identity, actual owner-scoped draft and export profile integration, unchanged legacy v1/v2 bytes, v3 round trips and bounds, seven-row tiled storage, cancellation and injected IO failure cleanup, progress and row-sized transfers. The original portrait host suite is also run separately because its shared local-edit model changed.

`RegionBoundedMemoryProbe` is an optional standalone probe rather than part of every rerun. Compile it with the suite, then invoke its main class under `-Xmx96m`. It generates a 6000×4000 source procedurally without retaining a full frame, processes a real grain region through the temporary candidate file, checks every output write against the finite brush support, and reports allocated bytes and scratch cleanup. Its timing describes the desktop JVM and is not a phone performance result.

Current public engine contract:

- `AdjustmentRegion` holds an immutable ID/name, enabled state and amount; ordered standalone `PhotoPortrait.Stroke` values; complete `PhotoAdjustments`; optional portrait operations; whole exposed-skin settings and semantic cache. Face-selection correction strokes are a separate concept.
- `compileBrush(width,height).weight(nx,ny)` returns oriented coverage without multiplying region amount. Coverage starts at zero. `withX` methods preserve other fields.
- `PhotoLocalEdits.regions()` is ordered. Existing copy operations preserve it. Empty lists retain the old v1/v2 wire representation; populated lists use v3. Region count, stroke/point totals and complete local-recipe bytes are bounded before storage.
- `LocalEditsPreviewProfile` appends regions after existing global/local/portrait stages. Ordinary colour is unrestricted by the semantic skin domain; only skin and portrait operations use it. Composition and borders still follow this processing.
- `SpatialPreviewFilter.Pixels.scratchDirectory()` can supply an app-private cache directory. Full-resolution branches use one disposable ARGB file, bounded to 512 MiB, and one-row transfers. No additional full-frame bitmap is allocated by the region renderer.

Later native UI validation is separate: these host results do not certify controls, touch navigation or Android storage behavior.
