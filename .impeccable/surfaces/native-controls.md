---
version: 1
slug: native-controls
current_version_code: 146
current_version_name: 0.28.9-beta
primary_target: app/src/main/java/cc/huevia/ui/AppDialog.java
related_targets:
  - app/src/main/java/cc/huevia/ui/AppNotice.java
  - app/src/main/java/cc/huevia/ui/PhotoEditorTypography.java
  - app/src/main/java/cc/huevia/ui/UiPalette.java
  - app/src/main/java/cc/huevia/ui/LocalAlbumPanel.java
  - app/src/main/java/cc/huevia/ui/UpdatePanel.java
  - app/src/main/res/values/native_styles.xml
  - app/src/main/res/values/native_controls.xml
  - app/src/main/res/values/styles.xml
---

# Direction contract

## Native controls 146 (current; scoped review complete)

The user chose 应用相册, then explicitly requested 手机相册 and app-owned native-control polish. This is an Operate refinement of the incumbent Android world. [Implementation and evidence](../../docs/native-ui146.md), [validation](../../docs/validation/native-ui146/validation.json), [review contract](../review/native-ui146/contract.md), [final review](../review/native-ui146/review.md). Fresh full scoped native review is `ship`, with no material fixes and all 25 required captures valid. Older version scores do not certify this work. No new world, comp, concept roll, production raster or global palette change is introduced.

THESIS: Keep confirmations, choices and short feedback visually coherent while preserving the native action and validation contract.

OWN-WORLD: Existing UiPalette warm-white/graphite grounds, terracotta/apricot accent roles, native sans sp type, drawn AppIcon strokes and Ripple feedback. Theme-role XML references the same palette values. Secondary windows resolve their supplied theme context through UiPalette.forTheme, including explicitly dark editor wrappers.

STORY: Existing app-owned confirmations, input validation, single/multiple choices and import actions use the shared finish. Their callbacks, choice adapters, enabled states and cancellation rules remain the caller's. Album sources stay exactly 应用相册 / 手机相册, including refresh; partial phone permission appears in the existing count scope as 已授权 · 共 x 张 rather than changing the four-character source label. Storage copy follows that vocabulary, while generic preset use says 应用中. 145's phone-album export and default new copy, 144's 轻量 label and 142's saved-file/current-edit boundary remain.

FIRST VIEWPORT: Compact native alert card with a 16sp medium title, 14sp message/choice text and 13sp action labels. Keep native buttons at least 48dp high, a 24dp card radius and a maximum 520dp dialog width with side clearance. Long action labels or three-button groups stack vertically. Required-update version text is 18sp, with existing progress, notes and actions.

Bare forms receive a 12dp outside gutter while custom internal input padding remains intact. Titles/messages use balanced wrapping. Checked rows show one indicator, and direct RadioButton/CheckBox marks have symmetric 8dp spacing. Destructive actions use error text and an error-colored outline over the card; the light text/background pair is about 6.1:1. Normal primary actions retain the soft tonal fill.

FORM: AppDialog.Builder still extends Android AlertDialog.Builder and creates an actual AlertDialog. Attach/layout decoration does not replace caller OnShow validation. Native list and choice models remain. AppThemeLight/Dark supplies common button, input, menu, spinner, checkbox/radio/switch, slider and progress styles. Foreground app-owned notices use AppNotice; system-owned windows retain their platform contract.

**The Native Contract Rule.** Style the existing dialog and native widgets without replacing business callbacks, adapters, selection state or mandatory-update cancelability. Preserve caller-installed validation and listeners. Use flat Ripple actions; do not reintroduce inherited button elevation that clips against the container.

**The Theme-at-the-Window Rule.** Resolve secondary-window colors from the themed context that draws them. Keep native semantic roles aligned with UiPalette instead of creating a second palette or forcing a light editor dialog.

SkinTonePicker's actual name input is constructed with its dialog's AppThemeDark context. The production view path is opened and cancelled without storing a swatch; both app themes verify the existing dark field/text pair (#33302C/#F6F1EB). This verifies view construction and theme consistency, not swatch-save/storage behavior.

**The Owned-Surface Rule.** AppNotice replaces the three foreground app-owned Toast call sites. Its 13sp message, 16dp rounded card, outline and top safe-area placement follow the app. Background service Toasts, permission prompts, external file pickers and Android installation UI remain platform-owned; this scope does not promise to restyle them.

Source audit before migration counted 99 stock builder occurrences across 16 files, plus 17 PhotoEditorTypography builder occurrences, 10 PopupMenus, two Spinners and nine checkbox/radio/switch constructs. The final migration audit has no remaining raw caller sites. These are source counts, not distinct runtime scenarios or passed checks.

Seven native configurations pass 33 checks each: 231 repeated assertion executions, not independent scenarios. Actual installed album-label refresh, category OnShow validation and SkinTonePicker name-view context are checked. Other confirmation, choice/import, menu, spinner, switch, notice and required-cancellation scenes are native component fixtures. The required-update model does not establish OTA/download/install acceptance. There are 25 required captures in the review packet.

Tested APK: `dist/huevia-0.28.9-beta-debug.apk`, 33,589,719 bytes, SHA-256 `ce58fc7ea5b35f6de5df6a327cfab810cf27cae142ed1f649ab0b41584423dcd`. Separate export regression passes 52 checks and publishes two distinct completed 2400×1600 MediaStore JPEG rows from the same source, whose hash remains unchanged. Four-grade JPEG encoding was not repeated. Same-APK [saved-version selection regression](../../docs/validation/native-ui146/versions-regression.json) passes 45 checks with no additional exports. The 231 native, 52 export and 45 selection executions retain separate scopes; only two actual JPEG publications are claimed. No physical-device, TalkBack, camera/RAW, transport, legacy-OS or performance claim. WeChat is at its authentication interface; requested File Transfer Assistant delivery awaits manual entry and no file has been sent.
