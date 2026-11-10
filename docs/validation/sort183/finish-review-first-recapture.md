disposition: recapture

## recapture

- `.impeccable/review/sort183/phone-05-selection-A-preserved.png` — invalid selection-A evidence: the header shows `已选 1 张`, but an open `时间排序` sheet covers the bottom edit/export/delete actions. Recapture the settled selection state with cancel, selected count, select-all and all three A actions visible; the sort sheet must be dismissed and the sort entry hidden or disabled, as required by `requirements.md`.
- `.impeccable/review/sort183/tablet-05-selection-A-preserved.png` — the same invalid state: selected-count header plus a sort sheet obscuring the A action dock. Recapture the settled tablet selection state with the complete A header and edit/export/delete dock, without the sort sheet.

All 21 required PNGs were opened and inspected as one batch. All 21 dimensions and SHA-256 values match the final successful runs in `capture-index.json`, bound to 183 / 0.30.29-beta delivery APK `6a50a4bebc1894cf535653b60d609ad273ab496fbf0399158ad5f34b59dbafdf`. The two invalid captures remain invalid despite that provenance. Large-text and dark-landscape selection captures show the expected action dock; they cannot substitute for phone and tablet evidence. Frozen `LocalAlbumPanel.showSort()` guards selection, so the images do not establish whether this is a production interaction defect or a capture taken before the prior sheet finished dismissing. A full review must restart from valid captures; no fidelity, ceiling or ship verdict is issued from this packet.
