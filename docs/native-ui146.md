# Native controls and album names 146

146 / 0.28.9-beta follows the user's confirmed 应用相册 name, subsequent 手机相册 correction and request to polish app-owned native styling. This is an existing-world Android Operate refinement. It uses the incumbent UiPalette, native sans typography, AppIcon strokes and Ripple feedback. It introduces no new palette, visual world, comp, production raster or HTML/CSS surface.

The tested artifact, installed-runtime results and 25 required native captures are bound to 146 below. [Fresh full scoped native review](../.impeccable/review/native-ui146/review.md) is **`ship`**, with no material fixes and all 25 required captures valid. Earlier review scores and source migration counts do not certify this version.

## Shared native dialogs

[AppDialog.java](../app/src/main/java/cc/huevia/ui/AppDialog.java) supplies a builder that still extends Android AlertDialog.Builder and returns a real AlertDialog. Styling attaches to the decor/layout lifecycle; it does not replace the caller's OnShow validation. Existing callbacks, choice adapters, selected state, disabled states and cancellation remain caller/native owned.

The finish uses a 16sp medium title, 14sp body/choice text, 13sp buttons, 48dp action targets, 24dp card corners and a maximum 520dp width with side clearance. Long action labels or three-button groups stack. Buttons clear inherited elevation/state animation and retain Ripple; disabled text remains visibly distinct. Native list choice models remain in place.

Bare forms receive a 12dp outer gutter while existing custom internal input padding remains intact. Title/body wrapping is balanced. A checked row shows exactly one native indicator; direct RadioButton/CheckBox graphics have symmetric 8dp spacing. Delete/clear actions use error text and an error-colored outline over the card, giving about 6.1:1 light-theme text/background contrast. Normal primary actions retain their existing soft tonal fill.

[PhotoEditorTypography.java](../app/src/main/java/cc/huevia/ui/PhotoEditorTypography.java) delegates both its builder and AlertDialog styling to the shared implementation. [UiPalette.java](../app/src/main/java/cc/huevia/ui/UiPalette.java) retains its existing color values; `forTheme` resolves explicitly themed secondary-window contexts, including dark editor wrappers.

[SkinTonePicker.java](../app/src/main/java/cc/huevia/ui/SkinTonePicker.java) constructs its name input with the matching AppThemeDark context. The actual production view path is opened and cancelled in both app themes, verifying #33302C field and #F6F1EB text. No swatch save/storage callback runs in this check.

## Default controls and foreground feedback

[native_styles.xml](../app/src/main/res/values/native_styles.xml), [native_controls.xml](../app/src/main/res/values/native_controls.xml) and [styles.xml](../app/src/main/res/values/styles.xml) connect AppThemeLight/Dark to common buttons, inputs, popup/list menus, two existing Spinners, checkbox/radio/switch controls, sliders and progress. New semantic XML roles reference the same incumbent light/dark palette. Existing menu items, selection models and listeners remain.

[AppNotice.java](../app/src/main/java/cc/huevia/ui/AppNotice.java) replaces three foreground app-owned Toast call sites: photo-detail invalidation, export-preview invalidation and album deletion feedback. It uses 13sp text, a 16dp rounded outlined card, at most 520dp width, top system-inset clearance, replacement of the preceding notice and existing short/long feedback timing. Its polite live region and accessibility announcement are implementation, not TalkBack acceptance.

Background service Toasts and OS-owned permission, file-picker and installation UI remain platform-owned. The request does not confer control of those external surfaces.

[UpdatePanel.java](../app/src/main/java/cc/huevia/ui/UpdatePanel.java) uses the shared dialog/button/window finish and reduces the prompt's version text to 18sp. Required-update callbacks and Back/outside cancellation restrictions remain. Download/install policy, network behavior and update publication are not changed by this styling pass.

## Labels and retained photo behavior

[LocalAlbumPanel.java](../app/src/main/java/cc/huevia/ui/LocalAlbumPanel.java) introduces the requested exact four-character source labels 应用相册 / 手机相册. Durable photo-storage wording uses 应用相册, the phone library/publication destination uses 手机相册, and generic preset use says 应用中. Partial phone access appears in the existing count scope, 已授权 · 共 x 张. Internal enum values, preference keys and private paths retain their identity.

The final native run verifies both labels after refresh and the real category dialog's existing OnShow validation. Earlier overwritten labels, duplicate choice marks, unbalanced bare-field gutters, mixed editor input context and low-contrast destructive treatment are corrected states, not design rules.

[145's fixed phone-album export/default new-copy behavior](export-album145.md), 144's 轻量 grade, [142's saved-file/current-edit boundaries](album-versions142.md) and [141's floating dock](album-floating141.md) remain. New decoration does not make an export, deletion, import, mandatory update or validation decision on the caller's behalf.

## Audit and validation

The before-migration audit at `.tooling/native-ui146/audit-before.json` reports 99 stock AlertDialog.Builder occurrences across 16 files, plus 17 PhotoEditorTypography builder occurrences, 10 PopupMenus, two Spinners and nine checkbox/radio/switch constructs. The final migration audit reports no remaining raw caller sites. These are source occurrences, not distinct dialog screens or runtime pass counts.

Tested APK: [huevia-0.28.9-beta-debug.apk](../dist/huevia-0.28.9-beta-debug.apk), 33,589,719 bytes, SHA-256 `ce58fc7ea5b35f6de5df6a327cfab810cf27cae142ed1f649ab0b41584423dcd`. Build and v2/v3 signature verification pass. [validation.json](validation/native-ui146/validation.json) records source hashes and scoped results:

| Native configuration | Passing assertion executions |
| --- | ---: |
| Phone | 33 |
| Font | 33 |
| Narrow | 33 |
| Dark | 33 |
| Tablet | 33 |
| Compact | 33 |
| Tablet landscape | 33 |
| Total | 231 |

These are repeated assertion executions, not independent scenarios. The installed shared controls, real album/category paths and actual SkinTonePicker name view are exercised. Other confirmation, single/multiple/import choices, menu, Spinner, switch, required-cancellation and notice scenes are component fixtures. The required-update fixture establishes cancellation/disabled behavior; it does not certify real mandatory-update policy, OTA, download or installation.

Separate export regression passes 52 checks and actually publishes two distinct completed, non-pending 2400×1600 MediaStore JPEG rows from the same source, whose hash remains unchanged. Four-grade JPEG encoding was not repeated. Same-final-APK [saved-version selection regression](validation/native-ui146/versions-regression.json) passes 45 checks and performs no additional exports. The 231 native, 52 export and 45 selection executions retain separate scopes; only two actual JPEG publications are claimed. Final source-hash comparison reports no drift and the APK identity matches the tested artifact.

The [review contract](../.impeccable/review/native-ui146/contract.md) and 25 required actual native captures are in [native-ui146](../.impeccable/review/native-ui146/). They include light/dark controls and destructive actions, input/choice/menu/dropdown models, album names, narrow/font/tablet/orientation variants, the actual editor name view and the retained export default. All 25 are valid in the final review. The import-choice fixture represents the retained camera/live destination model, not an edited-export destination selector.

Evidence uses an owned read-only Pixel 9 emulator API 37.2; additional sizes/orientations are viewport emulations. No physical-device, TalkBack, camera/RAW, transport, old-Android or performance acceptance is inferred.

The user requested delivery of the final APK to WeChat File Transfer Assistant. WeChat currently shows its authentication interface and awaits manual user entry. No file has been sent. No update-service publication, Git commit or push is claimed. Frozen older validation and unrelated global metadata remain unchanged.
