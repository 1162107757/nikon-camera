# Portrait mask and selection feedback — 116 / 0.23.5-beta

Candidate SHA-256: `bca8223091df1634dcabcc266b804dc4ceb1fec5e9d3ed3bbe6b7e98ba21b01e`.
**Not published:** the one upload attempt was rejected with the backend's
request/daily-write budget message. `publication/UPLOAD-BLOCKED.json` and the
actual UI screenshot document the blocker. The existing 64MiB/day budget counts
both chunk and final-object writes; this candidate needs 66,749,976 bytes across
both stages, and earlier releases already used part of this UTC day's budget.
The next daily reset is 2026-10-30 08:00 Asia/Shanghai. No quota was changed.

## Resulting behavior

Automatic face selection keeps the existing candidate detector, then runs bundled
landmarks and semantic skin inference locally. The semantic face-skin class covers
the visible forehead independently of the old eye-distance ellipse. Hair, body
skin, clothes and background are separate classes; eye, brow, lip and nostril
protection follows the detected landmarks. Components must connect to this face's
landmark seeds, and the other detected faces remain separate.

The resulting 128×128 skin mask and 468 landmarks are stored in the portrait's
version-2 data, retaining manual add/erase corrections and all existing adjustments
through normal edits, history, drafts, detail preview and full export. Version-1
drafts keep their original selections. Re-running automatic selection uses the
existing confirmation explaining that it replaces face selections and adjustments;
that action remains undoable.

Selection feedback uses warm white `#fff1e4`, with maximum alpha 38/255. It flashes
for 220ms, clears for 140ms, flashes for 220ms and then disappears. Re-selection
replays it; parameter changes, zoom, comparison and dismissal cancel it. The hint
does not change image pixels or saved edits.

## Evidence and scope

- `BUILD-IDENTITY.json` binds this APK to production Java, resources, assets, local
  JARs, native libraries and build/preparation scripts, including newly bundled
  dependencies.
- `SDK-LOADER-VALIDATION.md` and `final-apk-sdk-audit.json` cover model provenance,
  licenses, exact lossless restoration, APK size, signing, ABI packaging and the
  loader's cancellation/integrity checks. No model weights were quantized or
  converted for this release.
- `HOST-RESULT.json` records 690 passing checks for legacy data compatibility, semantic and landmark masks,
  manual stroke precedence, feature protection, bounds, rotations, aspect ratios
  and all eight EXIF orientations.
- `LOCAL-IMAGE-QUALITY.json` records actual offline production inference and final
  mask checks on the reported local occlusion case. It documents remaining
  sensitivity at the fine-hair/skin transition. Private user photos and their
  diagnostic images are excluded from this directory, packaged assets and the
  upload.
- `VALIDATION-RESULT.json` links the actual installed candidate's 1,835 passing
  native checks across phone, font 1.3 and landscape, with 39 screenshots and
  per-run cleanup/provenance. Both automatic faces have landmarks and semantic
  masks; saved and restored drafts retain them. Actual overlay pixels are subtle
  warm white with alpha at most 38. Full-canvas checks verify both pulses, the
  clear gap, clean editing after the hint and interruption behavior. Full export,
  detail and independently oriented EXIF6 pixels match exactly.

This is bounded verification on local fixtures, including the reported occlusion
case and a public-domain two-face fixture. It does not establish universal face or
occlusion accuracy. Manual correction remains available.

The universal APK is 33,374,988 bytes, below the existing 32MiB upload limit. All
64-bit libraries and all four LiteRT JNI variants have at least 16KB ELF load
alignment. The existing 32-bit `libc++_shared.so` variants retain 4KB alignment;
the independent audit reports that explicitly.
