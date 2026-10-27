## verdict

1. **Resolved — 1.3× label scaling.** Reopened the replaced `screenshots/portrait-large-font.png` and `screenshots/landscape-large-font.png`. Parameter labels visibly enlarge and remain legible without clipping; frame, exposure values and shutter retain their hierarchy. `prototype.css:2` now applies `calc(11px * var(--type))` to the named portrait and landscape labels, giving 14.3px at 1.3×, and the named landscape identity, battery and title clamps now scale. `REVIEW-CHECKS.json` reports 83 browser assertions passing, including the added computed-font checks and retained bounds/target checks.
2. **Resolved — inactive Sync-tab contrast.** Reopened the replaced `screenshots/entry.png` and `screenshots/board-main.png`. The inactive tab labels retain the warm visual hierarchy. `prototype.css:2` now uses #706A63 against #EEECE7; `FIX-MEASUREMENTS.json` records 4.52524:1, exceeding the 4.5:1 normal-text requirement.

No regressions attributable to this fix batch were observed in these four recaptures. This is the bounded scoring pass on the two findings from DESIGN-REVIEW.md; the other 15 refreshed captures were not re-audited.

## remaining

Clear for the scored fixes. Scoped ship means the browser-rendered design is ready for human review; it does not mean user approval, native Android implementation, real camera integration or live histogram validation. The original review's evidence limits remain in force.

disposition: ship
