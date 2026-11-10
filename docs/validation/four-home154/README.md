# Four native homes · 154 / 0.30.0-beta

Implemented only the native 预设／同步／相册／设置 roots and their source controls, following the [user-approved board](../../design-review/hyperactive-gallery-20261107/review/four-home-board.jpg). The [native screenshot board](native-four-home-board.jpg) shows the actual implemented roots; photos, connection and progress fixtures are explicitly test data. Photo processing, editor, detail, export and RAW retain their existing design and behavior.

Local APK: [huevia-0.30.0-beta-debug.apk](../../../dist/huevia-0.30.0-beta-debug.apk), 33,610,199 bytes, SHA-256 `9636cfe8dde97c1af3863754b16557ddf1620b75e2e6d3b9230a6705cc34b8b9`. The [manifest](manifest.json) freezes the candidate's six production-file hashes and the 70 native screenshot/report hashes. Frozen corrected evidence is in [native/](native/); initial review evidence remains separately archived under `.tooling/four-home154/pre-review-native`.

| Corrected native mode | Passing assertions |
| --- | ---: |
| Phone | 50 |
| Font 1.3 | 50 |
| Narrow | 50 |
| Dark | 50 |
| Tablet viewport | 44 |
| Compact | 45 |
| Tablet landscape viewport | 44 |
| Total repeated executions | 333 |

These checks cover the bounded home fixture flows, actual 48dp category targets with 36dp painted capsules, preset and album native search dialogs, source switching, selection, settings and transfer placement. They are repeated assertions across configurations, not 333 independent scenarios.

The [initial finish review](finish-review.md) remains **FIX** for the initial `e89be8…` candidate. Its only findings were F1 category paint/hit geometry and F2 passive local-caption spacing. The [scored verdict](verdict.md) reopened all seven corrected preset paths and resolved both findings, with no introduced material regression observed: **ship, limited to those scored fixes and direct regressions**. It is not a new whole-surface or whole-app acceptance. The [scope record](scope-preservation.json) records the unchanged downstream/editor block and named source hashes; [contrast](contrast.json) retains the exact tested color pairs.

Final-candidate [regression evidence](regression/) is kept separate from the home matrix and is frozen by the manifest: source-motion [phone 70](regression/motion/phone/report.json) plus [disabled-animation 9](regression/motion/reduced/report.json); Prisma [quiet-selection 10](regression/editor/selection-soft153-final154-20261107-202402/report.json) plus [editor-continuity 101](regression/editor/home154-final-continuity-20261107-202414/report.json), all passing on the same APK. These counts do not rerun or absorb the historical 151／152／153 matrices. No new end-to-end JPEG export is claimed.

Persistence is complete in [DESIGN.md](../../../DESIGN.md), the [native-home brief](../../../.impeccable/surfaces/native-four-homes.md), [sidecar](../../../.impeccable/design.json) and [PRODUCT.md](../../../PRODUCT.md). Home colors are isolated through `UiPalette.home`; base palette and Prisma 151／152／153 rules remain in force. See the [documentation log](DOCUMENTATION-LOG.md).

154 uses the current real preset-template simulation and packages no new demonstration photography. New showcase photographs belong to a separate authorized chat workstream for a later build; prototype imagery and emulator fixtures are not shipped photography or camera-effect proof.

All native evidence uses the owned Android 17／API 37 emulator; narrow/tablet/compact are viewport configurations. No physical phone was connected and no server publication occurred. Camera transport/throughput, production catalogs, physical devices, TalkBack, FPS, algorithms and whole-product acceptance are outside this record. The user canceled WeChat delivery; no APK was sent. Local delivery is available above.
