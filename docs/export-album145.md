# Direct phone-album export 145

145 / 0.28.8-beta follows the user's two screenshot corrections: exporting edited photos goes to the phone album, and saving a new copy is the default. This is a native Operate distillation of the incumbent flow. The adaptive UiPalette, native typography, rounded controls, fixed primary action, version choices and 144's 轻量 label remain.

The tested artifact and native evidence below are bound to 145. [Fresh full scoped native review](../.impeccable/review/export-album145/review.md) returns **`ship`**, with no material fixes and all eight required captures valid. This reviews the changed 145 workflow; earlier 143/144 evidence and scores retain their original scope.

Tested local APK: [huevia-0.28.8-beta-debug.apk](../dist/huevia-0.28.8-beta-debug.apk), 33,567,500 bytes, SHA-256 `aa21eb3c9384500c68e1558340ea30a2448113ce2a18ae1cdae13b95b50e347a`. Build and APK Signature Scheme v2/v3 verification pass. No upload, update-service publication, Git commit or push.

## A fixed export destination

[PhotoExportDialog.java](../app/src/main/java/cc/huevia/ui/PhotoExportDialog.java) fixes its target to `PHONE_ALBUM`. It removes the entire saving-location row, its inline App 内 / 手机相册 selector and the redundant App-retention explanation. It no longer reads or writes the edited-destination preference. Internal private result storage remains part of the existing pipeline, without another user-facing destination decision.

The normal CTA explicitly says 导出到手机相册 for one item or 导出 N 张到相册 for a batch. It retains the fixed 52dp action, availability checks, dimensions validation and disabled states. FULL/SHARE/CUSTOM remain independent from the quick-save grade. No quality, geometry or version-selection behavior is intentionally changed.

## A new copy by default

The existing 另存新副本 native circular checkbox starts checked on every advanced-dialog opening. The save-mode section starts collapsed and reports 保存方式 · 另存新副本. Expanding it exposes the existing checkbox and the shortened explanation 取消勾选后，复用已保存照片。

Explicitly unchecking selects guarded reuse. Existing same-version receipt, content, pending-state and ownership checks still apply; when all outputs are already saved, that path can open the saved result. The default checked path requests a fresh copy. Completion text describes fresh-copy versus reuse behavior truthfully. This default does not replace version/source guards, overwrite old public photographs or change frozen retry identity.

## Related entry points and boundaries

[AlbumPanel.java](../app/src/main/java/cc/huevia/ui/AlbumPanel.java) routes an edited export without an explicit frozen target to `PHONE_ALBUM` with `forceNewCopy=true`. Requests that already carry an explicit target/copy state retain it, including retries.

[PhotoFilterEditor.java](../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java) retains the JPEG-original confirmation and expected-source-hash check. It explains that filters, adjustments, composition, border and output-quality settings do not apply, and that original metadata can contain location. After accepting, the existing host callback now saves directly to the phone album as a new copy, without another destination dialog. Original bytes and metadata retain their existing semantics.

Camera-import/live-save destination workflows remain unchanged. RAW/NEF handling is outside this patch. [142's chosen saved-file/current-edit boundary](album-versions142.md), [141's floating selection dock](album-floating141.md) and [143's retained visual controls](batch-quality143.md) remain in force. The inline destination chooser and initially unchecked advanced-copy setting in 143/144 are historical behavior, superseded here. Current quick grades are 轻量 / 均衡 / 高清 / 原画; 轻量 remains 1280px/Q80.

## Validation and review

[validation.json](validation/export-album145/validation.json) binds the final source hashes, APK and native results. The six-mode run passes:

| Mode | Passing assertion executions |
| --- | ---: |
| Phone | 52 |
| Font | 45 |
| Narrow | 45 |
| Dark | 45 |
| Tablet viewport | 45 |
| Compact viewport | 45 |
| Total | 277 |

These are repeated assertion executions across configurations, not 277 independent scenarios. Phone mode actually exported the same owned fixture twice through the advanced default. It observed two distinct completed, non-pending MediaStore JPEG rows, each 2400×1600, and an unchanged source-byte hash. A legacy edited=APP_ONLY preference was seeded before opening and correctly ignored. These two publications exercise the advanced default; the JPEG-original callback and target-less fallback described above are source-inspected boundaries, not separate actual original-file export acceptance.

Slider UI checks still ran, but four-grade JPEG encoding was not repeated. The earlier four-grade output proofs remain scoped to 143.

The [review contract](../.impeccable/review/export-album145/contract.md) and eight required native captures are under [export-album145](../.impeccable/review/export-album145/): phone.png, phone-options.png, dark.png, narrow.png, large-font.png, tablet.png, landscape.png and user-1080.png. All eight are valid in the final review. The expanded options capture shows the checked new-copy choice and its concise reuse explanation. Phone and user-1080 share the 1080×2424 emulator viewport; the latter addresses screenshot width and does not reproduce the user's physical-phone height.

Evidence uses an owned read-only Pixel 9 emulator API 37.2 and owned fixtures. Narrow/tablet/landscape are viewport emulations. No whole-product, physical-device, TalkBack, camera/RAW, USB/Wi-Fi transport, legacy-OS or performance acceptance is claimed. Global DESIGN.md/sidecar metadata and frozen 143/144 records are outside scope.
