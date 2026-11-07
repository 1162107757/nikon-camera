# Portrait skin tones — 117 / 0.23.6-beta

Local build only. The user explicitly chose to retain the APK and resume upload
manually; no upload or automatic publication is scheduled.

The portrait panel adds one unified skin-tone tool: original, natural beige,
pink-white, cool-white, warm-white, warm-apricot, peach, cool-beige, wheat and tan,
plus custom colour and locally saved personal swatches. Presets and custom colour
share a 0–100 strength control. A custom HSV picker supports sampling a pixel
from the photo and returning to the picker. Real-photo preview is transactional:
cancel restores the original tone; confirmation creates one undo step. Personal
swatches are named, locally persisted, reusable and manageable, with a 12-card cap.

Each face retains its own immutable tone. Full-body scope performs local semantic
body-skin inference on demand, using the existing bundled model. Foreground
components are partitioned from the detected face seeds; unseeded components stay
unchanged. Clothing and background receive no body-skin weight. Overlapping
people and disconnected skin regions remain limitations of this semantic model,
which is not an instance-segmentation model. Face selections and manual add/erase
corrections continue to control face coverage.

Colour adaptation uses Oklab with a monotonic lightness mapping and hue-preserving
gamut compression, retaining local light/shadow and texture differences. Original,
zero strength and an identical sampled target produce unchanged pixels. The
existing brightness/texture/light settings retain their face-only scope. Version-3
portrait data stores tones and body masks, reads old v1/v2 drafts, and carries the
new fields through undo, draft restoration, detail preview and full export.

The draft-size guard is raised to a bounded 2MiB to accommodate the stored masks
and a full recipe. All model assets, native libraries and licenses are retained
from the verified 116 package. Private user photos and derived diagnostics are
excluded from this directory and the APK.

The final retained APK is `dist/huevia-0.23.6-beta-debug.apk`, 33,395,468 bytes,
SHA-256 `bc68248f6ee593491c8bc121dfa6ab7d8424f15af57953333b41e5e7db9ad2b2`.
`BUILD-IDENTITY.json` freezes all 287 production input hashes; `FINAL-STATUS.json`
and `VALIDATION-RESULT.json` record completion without modifying that frozen
identity. `PACKAGING-AUDIT.json` verifies the version, signatures, packaged new
classes and unchanged models/native libraries/notices.

`HOST-RESULT.json` contains 958 passing mathematical, compatibility and persistence
checks. `NATIVE-SUMMARY.json` links the final APK's 2,627 passing assertions across
phone, font 1.3 and landscape, with 51 screenshots. Actual original/zero-strength
and cancelled-custom preview pixels return exactly to the baseline; edits affect
only the selected face. Saved swatches and temporary test data are restored or
removed after each run. Full/detail/EXIF6 export pixels match exactly.

`LOCAL-BODY-QUALITY.json` contains a single offline real-image reproduction as
metrics only: contacting fingers have zero face weight and body weights
0.916/0.997/1, while hair, clothing and background have zero body weight. The
private source image and diagnostics were excluded; the remote fixture and probe
were removed and network settings restored. This bounded result does not claim
general instance-segmentation accuracy or physical-device performance.

The owned emulator was closed after all checks and confirmed absent from ADB.
