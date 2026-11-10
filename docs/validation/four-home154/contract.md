# Four-home implementation 154

Approved by user: “先就按照这个做一版吧”. Scope: native 预设 / 同步 / 相册 / 设置 roots and their source tabs. Approved visual artifact: docs/design-review/hyperactive-gallery-20261107/review/four-home-board.jpg.

Keep photo processing and all downstream editor/detail/export/RAW UI and behavior on incumbent design. Preserve real handlers, caches, permissions, connections, queues, selection limits, date grouping and version chooser. No prototype demo imagery is packaged in production APK; device probe fixtures only.

Implement warm paper, charcoal whole-tab selection, neutral floating controls, compact labels, source white inset, masonry photo cards, light connection entries, compact settings and download overlay separated from nav.

QA: bounded first combined device pass, one batched correction, final combined confirmation; fresh finish reviewer and documenter. Camera transport/server catalog/physical-device throughput are not certified by UI fixtures.
