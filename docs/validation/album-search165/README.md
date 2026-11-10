# Build 165: album thumbnails and expandable preset search

Local candidate **0.30.11-beta / 165**, not published. Full APK: `dist/huevia-0.30.11-beta-debug.apk`, 34,627,030 bytes, SHA-256 `d1b342b5791dfbb391a4b2b6fd00642b9063b574cbbfb43e5eb8910bda9b2a71`. Upload APK: `dist/upload165/huevia-0.30.11-beta-update.apk`, 31,333,565 bytes, SHA-256 `992644b188cabfce01732653938840c6bc1b867b6b53b6dc5a81be69b87d542b`.

The upload variant retains armeabi-v7a, arm64-v8a and x86_64; only the four legacy x86 native libraries are removed. All 88 retained payloads match the full package. Both use existing signer `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`; V2/V3 signature and 16 KiB alignment checks pass. The offline backend APK inspector accepts version / package / signer. See `update-payload-provenance.json` and `candidate.json`. No release API, COS object, website or production database was changed.

## Fixes

- Thumbnail completion and scroll-idle pumps update current visible matching image targets instead of notifying/rebuilding the whole adapter. Visible bitmap drawables retain their image even after LRU eviction. Epoch-aware pending jobs cannot clear a newer request for the same key; stale work cannot paint a recycled target.
- Search expands at the existing preset header, with search icon, text input, clear and cancel. Debounced filtering rebuilds only the result body so input identity, focus, cursor and IME survive typing. Cancel / app back collapse and clear it; queries retain source/category scope, with honest “loaded presets” wording online. Empty results provide a clear-search action. Activity state includes query / expanded state.
- The independently scoped [NP3 reference comparison](../np3-vitality165/README.md) documents the shared grading-brightness correction and its approximation limits.

## Accepted evidence

| Run | Scope | Result |
| --- | --- | --- |
| `baseline164-20261108` | API 37, 1440×3120 / 560 dpi, 2 MiB thumbnail cache, 6.5 s stationary observation | 108 tile replacements and 161 ready-to-placeholder regressions; diagnostic baseline, not a passing fix |
| `fixed165c-20261108` | Same API 37 pressure profile; full candidate before the colour-only revision | 0 replacements / 0 regressions; live search, clear, cursor, cancel and back pass |
| `fresh36-update165-final` | **Exact final upload APK SHA verified**, fresh Android 16 / API 36, 1080×2424 / 420 dpi, font 1.0, light | 504 observations, 6 loaded visible keys, **0 replacements / 0 regressions**; scroll / search flow passes without system ANR overlay |
| `fresh36-dark130-update165` | Same final upload APK, Android 16, app dark, font 1.3, visible keyboard and submitted state | Focus / back and native screenshots pass; no system ANR overlay |
| `wide-actual-dark130-165` | Exact final full APK, API 37, 1920×1200 / 240 dpi, dark, font 1.3 | Header, rail and search empty state reviewed |
| `compact-dark130-165` | Same final full APK, API 37, 1920×1080 / 420 dpi, dark, font 1.3 | Compact landscape header and result scroller reviewed |

The cache cap is deliberately reduced to force eviction; these counts are a deterministic UI regression measure, not an OEM performance benchmark. The 164 baseline did not record its installed APK hash, so it is not an exact archived-package certification. New final Android 16 runs verify the installed upload APK hash. The probe seeds only its own 42 MediaStore rows and removes their URIs, restores temporary app appearance / permission, and does not clear app data. Physical Samsung S24+ / Android 16 remains untested.

Earlier API 36 runs on the reused 157 AVD (`api36-fixed165-20261108`, `final-api36-165-20261108`, `phone-dark130-165`) were invalidated for visual acceptance because a **System UI isn't responding** system dialog covered captures. Their original reports are retained with separate invalidation records, not silently counted as accepted UI passes. `update165-api36-confirm` and `update165-api36-clean` detect and fail that overlay. A new task-owned data directory with 4 GiB RAM / 4 cores resolves the emulator state; the final exact-package runs above pass. `wide-dark-font130-165` was actually light because the prior app preference overrode system night mode; the named actual-dark run supersedes it.

Host regressions: 24,831 Flexible Color checks; 112,146 strict monochrome / FC checks; 161,928 standard-monochrome checks; 72 parameter-detail checks; 41,534,647 spatial assertions; NCP monochrome / structural / template / adaptation suites (2,953 / 68 / 2,168 / 98). The local full real-recipe corpus ZIP is absent and explicitly skipped; no corpus was downloaded or embedded. No real camera connection / transfer / RAW acceptance claim is made by this change.

## Scoped finish review

The search refinement keeps the existing warm paper / graphite home design, semantic palette, system sp, 48 dp controls and original source/category/navigation structure. Phone light, phone dark with large text / IME, wide dark and compact landscape screenshots were reviewed. The live input remains in the fixed header and does not open a modal. Clear and cancel remain labeled and reachable. This review is limited to the named controls and configurations; it does not relabel the frozen four-home 154 or editor reviews as a new whole-app approval.
