# Compact portrait submenu · 120

User correction: the portrait secondary menu should use the same layout and style as the primary menu, rather than two large blocks across the bottom.

`PhotoWorkspaceUi.styleTab` now owns the existing primary-menu appearance. Both `PhotoFilterEditor.styleCategory` for primary tabs and `PhotoPortraitDialog.refresh` for skin/face tabs call this helper. It retains the primary menu's 12 sp medium type, selected peach / unselected translucent-white text, 18 × 2 dp indicator with a 5 dp bottom inset, focus outline, ripple and horizontal padding. `tabHeight` uses the same font-scaled 48 dp calculation as the previous primary-menu row.

The secondary row now has two centered 72 dp labels with no layout weight. It uses the same menu background and font-scaled row height, with a minimum 48 dp touch target. The dock height includes the row's extra height at larger system font sizes. The skin and face content, automatic full-image skin detection, confirmed edits, custom-preview cancellation and tool memory remain unchanged from 119.

Only four production inputs changed from 119: version metadata, the shared UI helper, the parent editor and the portrait dialog. No renderer, model, recipe or persistence code changed. This is a focused native layout and interaction validation; unchanged model/host/export suites are not rerun or presented as new evidence.

The frozen local package and all 288 production inputs are bound by `BUILD-IDENTITY.json`. `PACKAGING-AUDIT.json` verifies signing, the unchanged signer, ZIP alignment, the unchanged 55 raw resource entries and the real DEX calls from both menu levels to the shared helper. The successful focused native runs passed **615 phone**, **615 font-scale 1.3** and **665 landscape** assertions: **1895 checks and 15 screenshots**. They include a real first-level editor screenshot and direct comparisons of its native Button styling, row geometry and indicator with both secondary labels, followed by the existing grouping interaction regressions. The root inspected the ordinary, large-font and landscape screenshots in one batch; no UI correction was required.

An initial large-font run was blocked near the end by Android's first-use fullscreen coach overlay. Its failed report and screenshot are retained separately. A runner-only change confirms that system coach during testing and restores the prior setting afterward; the same production APK then passed the complete large-font and landscape runs. The already-passing phone run retains its own harness provenance. Only the three complete successful runs count toward the 1895 assertions above.

Screenshots use the existing public-domain NASA fixture, with no user photograph included. Cleanup records cover the added primary-menu reference JPEG, editor drafts, all test fixtures, remote evidence, probe package, system settings and personal swatch preferences.

The package remains local and unpublished, following the user's manual-upload preference. No automation was created.
