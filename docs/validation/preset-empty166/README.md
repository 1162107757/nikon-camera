# Preset empty state — 166 / 0.30.12-beta

User request: remove the two buttons below search empty results and center the no-data message. Search empty results now show only the existing icon, title and hint. The header clear icon and Cancel remain available. The cache-directory footer is removed from preset empty states. Preset no-data messages center horizontally and vertically in the result viewport above the floating navigation; a fill-viewport ScrollView retains overflow access on short / large-font screens. Existing add / retry controls for other preset empty or error states remain available. Other app empty-state helpers are unchanged.

## Native review

One batched inspection reused the existing device probe, parameterized with online source / query `123`; no new layout unit tests were added. Four API 37 emulator configurations passed the existing focus / app-back / capture guards, with native screenshots reviewed for the requested change:

- `phone-light166`: 1080 × 2424, 420 dpi, font 1.0, light.
- `phone-dark130-166`: same phone size, font 1.3, app dark.
- `wide-dark130-166`: 1920 × 1200, 240 dpi, font 1.3, app dark.
- `landscape-dark130-166`: 1920 × 1080, 420 dpi, font 1.3, app dark; short viewport remains scrollable.

The icon and message are centered, the two removed buttons are absent, and the source / category / result headers and search controls stay in place. The probe filenames containing `keyboard` are inherited; the API 37 captures here do not show a keyboard and are reviewed as focused-input states, not a new IME or OEM certification. System display, density, font, and hardware-keyboard IME settings were restored. No physical phone, new algorithm, camera transfer or whole-app acceptance claim is made by this narrow visual change.

## Package

Full APK: `dist/huevia-0.30.12-beta-debug.apk`, SHA-256 `185a10b54cd09fe515d7edf04c23a0ba44346d755ad9143d359941d8c5c32d46`.

Upload APK: `dist/upload166/huevia-0.30.12-beta-update.apk`, 31,333,565 bytes, SHA-256 `b4a87c12008e79a469d4ca954fe4ce8c476a12fa7d39e18f63ca742c1803fba5`.

The upload variant removes only four legacy x86 native libraries, retains ARM32 / ARM64 / x86_64 and has 88 payloads identical to the full APK. V2/V3 signatures, the existing certificate, 16 KiB alignment, ZIP contents, and the offline backend APK inspector pass. The installed APK SHA is recorded in `candidate.json`; 165's frozen APK is preserved. No production release, upload or website change was performed.
