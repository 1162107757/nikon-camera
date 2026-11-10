# Local brush163 documentation handoff

Recorded 2026-11-08 after the final scoped review returned `ship`, with no material fixes. This pass merged only adjustment-editor rules into the existing documents; it did not redesign the visual world.

## Ground truth

- Built sources inspected: `PhotoFilterEditor.java`, `PhotoPaletteDialog.java`, `PhotoCleanupDialog.java`, `PhotoColorDialog.java`, with representative `PhotoWorkspaceUi.java` and `PhotoPrismaStyle.java`.
- Direction: [contract](../../../.impeccable/review/local-brush163/contract.md). Final outcome: [review](../../../.impeccable/review/local-brush163/review.md). The earlier [capture gate](../../../.impeccable/review/local-brush163/review-capture-gate.md) remains historical; the landscape-curves replacement was made from the same exact APK and verified at original resolution before that final review.
- Local APK: `dist/huevia-0.30.9-beta-debug.apk`, version 163 / `0.30.9-beta`, 34,622,934 bytes, SHA-256 `f64a5c5815d766e13444752abace0a434aabaacddabbd86a763daa5b6a79558b`.
- [Feature manifest](../../local-brush163.json), [native summary](summary.json) and [21 required captures](../../../.impeccable/review/local-brush163/capture-index.json) retain their identities. Main 2,406 + supplemental 970 = 3,376 repeated native checks; 159 retained RAW checks and host matrices remain separate units.

## Durable rules recorded

`DESIGN.md` gains one component subsection for the 48dp direct brush entry, visible local scope and final-Apply transaction boundary. Existing Prisma materials, compact native sans/sp, circular icon family, white slider thumbs and yellow action semantics are inherited; no token primitives were added. New local scope is neutral over committed global settings, automatic parent cleanup cannot silently become global, and repaint preserves parameters. Cancel returns to its parent without provisional writes; innermost Apply commits one main undo and closes ancestors.

`.impeccable/design.json` adds the 163 scoped implementation/evidence record and updates its current photo-workspace pointer without relabeling 151/152/153 records. `.impeccable/surfaces/photo-filter-editor.md` advances metadata to 163 and prepends the current narrow direction while retaining every historical section. `PRODUCT.md` is unchanged in this pass: the detailed feature truth remains in the scoped manifest and surface record.

## Verification and limits

Documentation-only structural checks passed: sidecar JSON parsing, current 163 metadata and pointer, exact narrative-rule parity, all 21 expected capture paths, and continued presence of the 151/152/153 records. Edits were applied as bounded insertions plus current metadata updates; unrelated document text was preserved. No source, tests, build settings, APK, RAW162 feature manifest or emulator state is changed. No build or device checks are rerun. Context-mode could not start its configured Node or Python subprocesses (`ENOENT`); bounded PowerShell/rg reads were used for this pass.

The final ship disposition covers this adjustment-page extension and direct regressions on emulator evidence. Filters are excluded; portrait remains separate. No physical phone/camera, whole-app or new RAW acceptance is inferred, and the APK remains local and unpublished. An invalid historical capture is not canonized as a design rule; the final review found no new visual defect to canonize.
