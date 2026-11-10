#173 · Paint and release repair

Local **0.30.19-beta /173** candidate, not uploaded or published.

The user asked to simplify repair to painting with a finger and releasing to erase. The default now opens PhotoEraseDialog directly: paint a mark, release, receive a local automatic repair. Each successful stroke adds one inner undo. A single Complete action commits one parent transaction and saves through the existing draft/version path; Cancel discards the tentative session. The default dock contains brush size, undo/redo, selection visibility and More. Manual selection/source dragging, feather/blend and old saved repair editing remain under More → 手动取样修补. The four adjustment entry icons retain170's26dp line-icon rule.

## Processing and limits

PhotoPatchSampler matches unselected surrounding context against real, opaque clean donor texture outside the entire marked region plus a safety rim. Work uses an immutable, oriented guide up to384px per side. The normalized donor translation is frozen into the existing v7 PhotoPatch recipe, so reopening does not reselect a random source. The established feather/colour-matching renderer is unchanged and shared by preview/export; destination alpha and zero-mask pixels remain exact. No cloud upload, external model or generative/semantic reconstruction is introduced. This is a local small-area texture repair; unsuitable broad strokes can still copy unwanted structure. The inherited16-repair limit remains, with a recoverable status and deletion/undo access.

The photo does not change during a held stroke. Sampling and rendering run off the UI thread; only a successful latest result changes edits/history. Failure/cancel leaves the model unchanged; dismissal interrupts/discards late results. Pointer cancellation, focus loss and a second finger discard the unfinished stroke; two fingers only navigate. Display coverage remains until explicitly hidden, never enters exported pixels, hides during slider dragging and restores the chosen visibility on release.

## Frozen artifacts

- Full: `dist/huevia-0.30.19-beta-debug.apk`, SHA256 `c8745941655c7995e5d704be482eb4aa2e350afd22d1aab867c02b55ddd009c7`.
- Signed delivery: `dist/upload173/huevia-0.30.19-beta-update.apk`, SHA256 `031912d18d80094a55e2485083bacfe9ede604e20538fce2f095d435ccc1f9fa`,31,370,429bytes, below32MiB.

The size variant removes only four obsolete x86 libraries. All88 retained payloads are byte-identical; ARM32/ARM64/x86_64 remain. Existing certificate, v2/v3 signature,16KiB alignment and backend offline inspection passed. Exact signed bytes were separately installed/cold-launched on the owned API36 emulator; see upload-smoke.json for timing/scope. No public publish/upload occurred.

## Verification boundary

- **46,702** automatic sampling assertions, including repeated per-pixel exterior/alpha/donor checks, deterministic plain/gradient/texture blemish recovery, edge/transparent/cancel/failure cases and existing v7 serialization/render roundtrip.
- Existing **43,230** local-edit and **153,740** repair renderer assertions passed, including old EXIF/alpha/order and24MP bounded-stream coverage. Their scope remains separate from new automatic-source matching.
- Exact full source APK: four API36 configurations (phone1080×2424; narrow/font1.3 840×1890; tablet1600×2560; landscape/dark2424×1080),154 native checks and8 original PNGs each,616/32 total. Actual finger down/move/up dispatch, automatic render/exterior/alpha, one-undo-per-stroke, repeat/error recovery, explicit eye/slider visibility, focus/pointer/pinch, legacy access, parent transaction and real saved draft/reopen. One intentional renderer IOException injection per configuration verifies atomic failure.

[Source identity](source-candidate.json), [capture index](capture-index.json), [package](package-candidate.json), [payload proof](payload-provenance.json), [offline inspection](apk-inspection.json) and [signed smoke](upload-smoke.json) bind this evidence. Permanent source/tests use the actual installed implementation by reflection, no substitute production classes. The isolated evidence harness under `.tooling` has byte-identical probe/run sources to the promoted permanent flow.

One bounded visual self-inspection batch covered all four state sheets plus full phone/landscape defaults. No additional material layout defect was found. Independent review follows at .impeccable/review/erase173/review.md. No production raster changed or HTML/CSS detector ran against native Java. The public-domain NASA portrait and unsuitable larger gestures are transaction/pixel QA, not a successful blemish/object-removal demonstration; known-background host fixtures check small-blemish recovery separately. No physical Samsung/Hongmeng, frame-rate, semantic/large-object reconstruction, new full-export matrix or whole-app/public-OTA acceptance is claimed.171/172 search and source-tab fixes remain separately frozen and documented by their owner.
