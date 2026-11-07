# Automatic haze and noise cleanup host checks

Run `./tests/cleanup-host/run-host.ps1` using PowerShell and JDK 17. The JVM heap is limited to 96 MiB. Output is written to `.tooling/cleanup127/engine`.

`legacy-vectors.txt` was captured by running `CleanupLegacyVectors` against the unchanged 126 production engine before implementing cleanup. It covers 65,536 packed ARGB outputs and exact v3/v4 local/PED6/PED7 draft bytes and identities, including active and zero-strength palette state. The prior palette golden adds 294,912 legacy pixel outputs and older wire identities.

`PhotoCleanupTest` uses synthetic latent images with a known linear-light atmospheric veil, independent original-resolution Gaussian-noise patches, a sharp brightness edge, pale backgrounds, soft mist, alpha/transparent pixels, and both the per-pixel and spatial regional branches. It checks strict persisted bounds, authenticated malformed data, state/copy/undo/recipes, intensity zero, immutable analysis, phase order, source-size noise scaling, and exact pixels outside brush coverage. Frozen haze output is compared at matching normalized coordinates at 80×60 and 240×180.

`PhotoCleanupBoundedTest` processes every pixel in a virtual 6000×4000 source separately for haze restoration and denoising, under `-Xmx96m`, without allocating a full-image Java array. It additionally cancels a 24 MP regional branch and checks that its private scratch file is removed. The virtual adapter rejects rereads of already overwritten original rows. Runtime and sampled heap observations are host diagnostics, not phone performance measurements.

The estimator computes robust statistics; it is not semantic scene recognition. It cannot reliably distinguish every intentional low-contrast scene or every fine texture from noise. Confidence gates reduce recovery on pale or featureless scenes, while a strength slider remains available. There are no new AI models, cloud calls, or private user image fixtures. Native tests separately validate the Android original-file decoder and true 100% patch acquisition.
