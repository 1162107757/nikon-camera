# Manual selection feedback · 124

Focused reflection-only Android instrumentation. It opens the exact installed
`PhotoBrushDialog` over an in-memory generated gradient. It does not package
production classes, import library records, use private photographs, connect a
camera, create drafts, or change image-adjustment parameters.

The phone run checks real Canvas frames: strong warm white, old soft warm white,
strong warm white, then exactly the old soft display. It compares the support
outside the brush, underlying source pixels, cached mask, region and undo state.
It also covers ongoing paint/erase, undo/redo, two-finger navigation, dismissal,
completion's clean gap, reopening an existing region, and the system-animation
disabled single-highlight fallback. The font and landscape runs exercise the
same visual sequence and completion without duplicating the interaction edges.

Build with `build.ps1`. Install the final candidate separately, then use `run.ps1`
with its exact SHA, explicitly handed-off owned emulator serial, and mode. The
runner restores font, airplane, fullscreen confirmation and animator duration,
uninstalls only the QA package, stops the target, and leaves exact remote evidence
directories for the test owner to remove after pulling and recording them.
