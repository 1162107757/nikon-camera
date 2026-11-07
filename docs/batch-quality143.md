# Batch actions and export polish 143

143 / 0.28.6-beta refines three existing native Android surfaces requested by the user: the batch action menu, quick-save quality selection and advanced export. It retains the incumbent warm-white/graphite/peach visual world, AppIcon strokes, native sp typography and Ripple feedback. No new visual world, comp, concept roll, quality board, production raster or global design metadata is introduced.

[Independent review sequence](../.impeccable/review/batch-quality143/review.md): the full scoped review found one inherited quick-save button-shadow clipping issue and no other material issues. After its narrow correction, the final verdict-only follow-up returned **`ship`** for that scored fix. All 14 required recaptures are valid, and no regressions were observed. This disposition covers the scored fix, not whole-surface acceptance; the implementation and tests below retain their stated scope.

Local adaptive-theme artifact: [huevia-0.28.6-beta-debug.apk](../dist/huevia-0.28.6-beta-debug.apk), 33,567,500 bytes. SHA-256: `6e7033811f924c6ebba63da9ddf66a15383b6ca3e00a8bb1cdd269d0aae5f5de`. No upload, update-service publication, Git commit or push was performed.

## Batch action sheet

[PhotoBatchActionsDialog.java](../app/src/main/java/cc/huevia/ui/PhotoBatchActionsDialog.java) replaces the stock rectangular batch AlertDialog with a themed bottom card. It is at most 560dp wide, has 26dp corners, 12dp outside side clearance and an 8dp bottom offset. The 17sp title and 12sp runtime selection count precede five 14sp rows with 22dp AppIcon strokes. Rows are at least 56dp high; the close target is 48dp. Thin inset separators group related actions. The three-photo screenshots use owned QA fixtures; production shows the actual count.

Existing callback IDs remain 0 套用滤镜, 1 我的配方, 2 导出照片, 3 自然精修 and 4 同步人像设置. The last action retains its first-selected-photo meaning. A chosen row dispatches once; close, outside tap and Back dispatch nothing. [AlbumPanel.java](../app/src/main/java/cc/huevia/ui/AlbumPanel.java) retains the existing routes. The scroll viewport itself clips to the rounded outline, so a short viewport preserves bottom corners while allowing the last action to scroll into view.

## Four quick-save grades

[PhotoQuickSaveDialog.java](../app/src/main/java/cc/huevia/ui/PhotoQuickSaveDialog.java) uses the app's adaptive light/dark card, retaining preview/version context with a 17sp title and a four-stop native SeekBar. The slider and its four single-line 12sp label buttons have 48dp targets. The thumb and label centers share positions; horizontal padding is set to width/8 before `SeekBar.onSizeChanged` updates drawable bounds. Grade details and active labels update with either dragging or a label tap.

[PhotoExportQuality.java](../app/src/main/java/cc/huevia/album/PhotoExportQuality.java) supplies the actual export spec to the existing queue:

| Grade | Long-edge ceiling | JPEG quality | Actual JPEG from 2400×1600 fixture |
| --- | --- | --- | --- |
| 省空间 | 1280px | 80 | 1280×853 |
| 均衡 | 2048px | 85 | 2048×1365 |
| 高清 | 4096px | 92 | 2400×1600 |
| 原画 (default) | Full dimensions | 95 intent | 2400×1600 |

Resolution remains per photo through [PhotoExportSpec.java](../app/src/main/java/cc/huevia/album/PhotoExportSpec.java), preserves aspect ratio and never upscales. The 4096 ceiling remains enforced for 高清. “原画” describes the existing full-output route and its nominal Q95 intent; saved-result reuse and original-file routes retain their own existing byte semantics.

Quick save explicitly requests a new phone-album copy. 更多设置 opens the existing advanced page, whose FULL/SHARE/CUSTOM modes remain independent; this change does not transfer the quick grade into that page or back.

Quick-save Button controls explicitly clear the inherited state animator, elevation and translationZ, retaining the native Ripple. Their rounded shape remains flat within the sheet.

## Advanced export and choices

Quick save, advanced export, version choices and check marks read [UiPalette.java](../app/src/main/java/cc/huevia/ui/UiPalette.java), so light mode stays light and dark mode follows the existing dark palette. Advanced selected modes/destinations use the neutral card over a container track. Save actions and checked marks use the softer primaryContainer/onPrimaryContainer colors instead of a large bright-peach fill. Accent remains on the grade rail and concise actions. This is a scoped application of the incumbent palette, not a new global token system.

[PhotoExportDialog.java](../app/src/main/java/cc/huevia/ui/PhotoExportDialog.java) uses a 72dp thumbnail and 14sp bounded filename. A single photo has a 22sp dimension readout. Batch items each have one 12sp filename-and-size row, without the redundant large count. Long names ellipsize with full accessibility text. Compact 13sp metadata and mode tabs with a 20dp outer radius, 16dp selected radius and 4dp equal inset keep the existing information dense and legible.

Saving location expands inline with two 48dp choices, App 内 and 手机相册, instead of opening a stock radio AlertDialog. Accepting a destination continues through the existing target/reuse/extra-copy logic. App-only clears the phone-only extra-copy choice. Original-file and saved-result guards remain in force. The 52dp save action remains fixed below scrolling content. Advanced export explicitly uses the nonfloating AppThemeLight/AppThemeDark full-screen theme from [styles.xml](../app/src/main/res/values/styles.xml); its status/navigation bars share the export surface color and select icon brightness by theme.

[PhotoChoiceCheck.java](../app/src/main/java/cc/huevia/ui/PhotoChoiceCheck.java) draws a 22dp circular mark while retaining native CheckBox/CompoundButton behavior, keyboard handling and accessibility state. It is used for saved-version, all-version and extra-copy choices; changing its mark does not alter selection semantics.

[142's saved-file/current-edit contract](album-versions142.md) remains binding: saved choices use their exact own files; only explicit 当前编辑 carries its frozen active profile; version choices survive advanced settings/back. Batch defaults to each photo's selected saved file, and all-version export stays opt-in. [141's floating dock](album-floating141.md), source lock, Back behavior and cancellation boundaries remain unchanged. The Spinner and native square checkbox appearance recorded in 142 are historical, superseded display choices. Frozen 142/141/129 evidence remains version scoped.

## Validation and limits

[validation.json](validation/batch-quality143/validation.json) binds the final APK and source hashes. Native reports under [final](validation/batch-quality143/final/) pass:

| Mode | Passing assertion executions |
| --- | ---: |
| Phone | 60 |
| Font 1.3 | 44 |
| Narrow | 44 |
| Dark | 44 |
| Tablet viewport | 44 |
| Compact viewport | 44 |
| Total | 280 |

These are repeated assertion executions across configurations, not 280 independent scenarios. Phone mode produced four actual JPEGs with the dimensions and requested grade qualities shown above. Tests exercised real grade dragging, selection/detail updates, label/thumb center alignment, cancel-without-dispatch, compact last-row reachability and actual inline destination switching. Five menu callback IDs were checked with a spy; the real export-row route was checked separately. The evidence does not claim completion of all five downstream rendering operations.

[versions-regression.json](validation/batch-quality143/versions-regression.json) records 45 passing version-selection regression assertion executions on the same adaptive APK, including real selected saved files, multi-select, advanced/back retention and saved-version/draft isolation. This separate regression produced no additional actual exports. The 280 matrix executions and 45 regression executions retain their separate scopes. The 11 exports recorded for 142 remain historical evidence for 142.

The [review contract](../.impeccable/review/batch-quality143/contract.md) and 14 fresh menu/quality/export captures are under [batch-quality143](../.impeccable/review/batch-quality143/), including explicit light and dark export/quality captures. Expanded [phone-destination.png](../.impeccable/review/batch-quality143/phone-destination.png) shows both inline targets. The optional final [versions.png](../.impeccable/review/batch-quality143/versions.png) adds version-picker evidence. Earlier forced-dark export colors, stale rail bounds, cropped compact corners, the clipped inherited button shadow and collapsed-only destination capture are superseded by corrected source/captures, not current design rules.

All device evidence uses the owned read-only Pixel 9 emulator API 37.2 and owned bundled JPEG fixtures. Narrow/tablet/compact are viewport emulations. No physical phone/tablet, camera/USB/Wi-Fi transport, old Android, TalkBack or performance acceptance is claimed.
