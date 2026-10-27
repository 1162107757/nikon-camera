# F1 correction verdict

**Verdict: SHIP at this scope. F1: RESOLVED.**

Reviewed only F1 from [FINISH-REVIEW.md](FINISH-REVIEW.md). The final local APK is `dist/huevia-0.21.7-beta-debug.apk`, SHA-256 `9dcc4dc793d8bb4ddfd89d5bd9b62ff95152e652b33b6ef7d04d9a1fee963ad6`. Its computed hash, the current `AlbumPanel.java` hash, and all three report hashes match [SOURCE-IDENTITY.json](SOURCE-IDENTITY.json) and [FINAL-VERIFICATION.json](FINAL-VERIFICATION.json).

[AlbumPanel.java](../../../app/src/main/java/cc/huevia/ui/AlbumPanel.java), lines 3630–3635, now rejects `visible == null` when the resolved original and selected file have different canonical paths. It throws `保存版本参数不可恢复，请改选原图。` while preparing targets; `PhotoAdjustmentCopy.apply` occurs only after the complete loop. This prevents the neutral fallback from overwriting a historical target's filter, crop, and border. Originals and targets with recoverable visible parameters retain their existing path.

Each supplied final native run reports **67 PASS**:

- [Portrait](9dcc4dc7/20261026-220723-phone-80fedf/20261026-220723-phone-80fedf/report.json)
- [Font 1.3](9dcc4dc7/20261026-220736-font1.3-2ebb2f/20261026-220736-font1.3-2ebb2f/report.json)
- [Landscape](9dcc4dc7/20261026-220750-landscape-425742/20261026-220750-landscape-425742/report.json)

All include `historical-effect-resolves-real-original`, `historical-parameters-unavailable`, `unavailable-saved-version-zero-target-writes`, and `unavailable-saved-version-no-receipt`. The [fixture](../../../tests/photo-color-device-probe/src/cc/huevia/colorqa/PhotoColorProbe.java), lines 66–78, uses the JPEG renderer and production source-link validator, retains a mismatching exported draft, confirms through the batch UI, and checks both target states. All three `05-unavailable-saved-version.png` captures show the complete rejection message and acknowledgment button without clipping.

Limits: the missing-draft variant is covered by source inspection of the same null guard, rather than a separate runtime fixture. The earlier 15-capture visual approval stands; this pass inspected only F1's three error captures. No build, test rerun, emulator launch, production edit, or web detector was performed. Evidence supports native emulator behavior, without real-phone, camera, MediaStore-publication, or Nikon/NX equivalence claims.
