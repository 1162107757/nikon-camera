# Portrait skin and face groups · 119

User request: separate skin work from face processing inside 调节 → 人像.

The default **皮肤** group directly shows the existing global skin-tone scope, swatches, custom-color entry and intensity slider. It automatically recognizes exposed skin across the photograph without requiring any face selection. **面部** contains the existing seven face adjustments, healing and selection correction. The two group controls stay outside the scrolling dock and have 48 dp touch targets. The existing dark palette and peach selection underline are retained.

Switching groups preserves the confirmed recipe, selected face, advanced per-person tone scope, last face tool and last adjustment. An unconfirmed custom-color preview is cancelled before leaving the skin group. Returning to the face group clears selection overlays and brush gestures. Reopening a recipe with active per-person tones restores that scope and the first affected face. Preparing the global automatic mask no longer increments the user-edit revision, so a face-detection operation queued immediately after entering the editor remains valid.

Only `app/build.gradle` and `PhotoPortraitDialog.java` changed from the frozen 118 production inputs. The skin segmentation, masks, color transforms, recipe format, draft storage and rendering/export pipeline are unchanged. This is a focused UI and asynchronous interaction validation; the 118 renderer/model/real-photo results remain historical evidence for that unchanged code, rather than newly executed 119 tests.

`BUILD-IDENTITY.json` binds the exact local APK and all 288 production inputs. `PACKAGING-AUDIT.json` confirms APK v2/v3 signing, the unchanged signer, 16 KB ZIP alignment and all 55 raw resource/native/model/notice entries byte-identical to 118. The focused native checks passed on the owned emulator: phone **369**, font scale 1.3 **369**, landscape **385**, for **1123 assertions and 12 screenshots**. The root reviewed the skin and face layouts across all three modes and the rotation state in one batch; no UI correction was needed. `VALIDATION-RESULT.json` binds those reports, their cleanup records and the frozen package.

Native screenshots use the existing public-domain QA fixture. No user photo is included. Fixture photos and remote evidence were removed, the probe was uninstalled, swatch preferences and system settings were restored, and the app was stopped. These checks cover the actual installed production panel and its interactions; they make no new claim about physical-phone latency or segmentation accuracy. Example screenshots: [skin group](skin-group.png), [face group](face-group.png).

Publication remains **local package only**, following the user's request to retain the APK and resume uploading manually later. No upload or scheduled task is part of this change.
