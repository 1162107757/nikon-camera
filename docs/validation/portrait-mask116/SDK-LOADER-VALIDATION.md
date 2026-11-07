# Candidate 116: SDK, model loading and APK audit

This is a local validation record for candidate `0.23.5-beta` / versionCode 116.
It does not record an upload or publication. This audit did not read, upload or
run inference on user photographs. It did not access an Android device.

## Final candidate artifact

| Check | Observed result |
| --- | --- |
| APK | `dist/huevia-0.23.5-beta-debug.apk` |
| SHA-256 | `bca8223091df1634dcabcc266b804dc4ceb1fec5e9d3ed3bbe6b7e98ba21b01e` |
| Bytes | 33,374,988 |
| Limit | 33,554,432 bytes (32 MiB) |
| Remaining | 179,444 bytes |
| ABI set | arm64-v8a, armeabi-v7a, x86, x86_64; 16 native libraries |
| All 64-bit native ELF LOAD alignments | At least 16,384 bytes |
| LiteRT JNI ELF LOAD alignments | At least 16,384 bytes in all four ABIs |
| `zipalign -c -P 16 4` | Exit 0 |
| Manifest | `extractNativeLibs=true`, versionCode 116, versionName `0.23.5-beta` |
| APK signature verification | Exit 0; v2 and v3 signatures verified |

The existing `armeabi-v7a/libc++_shared.so` and `x86/libc++_shared.so` have
4,096-byte ELF LOAD alignment. Consequently this record does **not** claim that
every native library in every ABI has 16 KiB alignment. The exact per-library
hashes, sizes and alignments are in [final-apk-sdk-audit.json](final-apk-sdk-audit.json).

The final APK contains both portrait models, complete LiteRT/MediaPipe license
files, their README and build identity schema 2. The semantic asset's ZIP method
is STORED (0): 13,881,786 bytes, packed SHA-256
`9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0`.
Inflate plus inverse byte-plane shuffle restores exactly 16,371,837 bytes and
the official model SHA-256
`c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0`.
The original model weights and metadata are unchanged. The landmark asset is
2,553,590 bytes with SHA-256
`c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5`.

## Host loader validation

The exact production `FaceSkinModel.java` was compiled with JDK 17.0.19 against
the Android API 35 stub JAR. The checked-in
[FaceSkinModelHostTest.java](FaceSkinModelHostTest.java) executes only the pure
`decode(InputStream, BooleanSupplier)` method. The inputs are the bundled packed
model and the cached, SHA-pinned official Google model, never a photograph.

The final-source rerun exited 0:

```text
PASS FaceSkinModel host decode: 14 checks; official byte-exact SHA, bounded stream, cancellation, corruption, trailing bytes, short reads, stream ownership.
```

The assertions cover a read-only direct buffer, native byte order, exact limits,
the official restored SHA, independent buffer positions, truncated streams,
trailing compressed bytes, corrupt headers, a valid alternate zlib header whose
packed hash must still be rejected, immediate and mid-load cancellation,
decoded output beyond the fixed size, short reads and caller-owned stream
lifetime. The decoder checks both compressed and restored SHA-256 identities
before a successful result can enter the cache.

The preparation script passed twice, including cached/offline reuse and its
byte-exact round trip. Both PowerShell scripts passed AST parsing. The actual
asset loop from `build-apk.ps1` was also executed against an isolated archive:
the semantic asset became STORED with its pinned bytes, while an ordinary
asset retained deflate compression and its contents. No full APK build was
started by this independent audit.

## Production source review

`FaceSkinModel` retains only the verified read-only direct model buffer and
returns independent native-order views. It does not retain a Context or
Activity, initialize JNI or download anything. Failures and cancellations do
not populate its cache; the loader closes the bundled asset, while the pure
decoder leaves input-stream ownership with its caller. Inflate and hash work
check cancellation at bounded blocks, and decoded and packed lengths are
fixed and checked.

`PhotoFaceSkinMask` closes its Interpreter with try-with-resources and recycles
its temporary crop in `finally`. Input and output shapes/types are checked.
It rejects non-finite logits, performs one stable six-class softmax per pixel,
and bounds its component queue to the mask raster. It checks cancellation per
row and before/after native inference. Cancellation is cooperative; the current
CPU inference call completes before the following check. A fresh Interpreter
is scoped to each refinement batch, with the verified model buffer retained
for its full lifetime.

No additional actionable loading, lifecycle, numerical or resource defect was
found in those two reviewed files. Source hashes are recorded in the JSON.
This host/static audit does not establish portrait segmentation quality,
multi-person accuracy or Android end-to-end behavior; those require the
separate private device validation.

The direct semantic model output is logits, not probabilities. Its final
producer is CONV_2D, and embedded `SEGMENTER_METADATA` (`V001`) sets activation
to SOFTMAX (enum 2). The official graph reads that metadata and applies stable
softmax after inference, matching the production helper:

- [Official model source](https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite)
- [Official model card and Apache-2.0 license statement](https://storage.googleapis.com/mediapipe-assets/Model%20Card%20Multiclass%20Segmentation.pdf)
- [Activation metadata lookup](https://github.com/google-ai-edge/mediapipe/blob/v0.10.32/mediapipe/tasks/cc/vision/image_segmenter/image_segmenter_graph.cc)
- [Official stable-softmax postprocessing](https://github.com/google-ai-edge/mediapipe/blob/v0.10.32/mediapipe/tasks/cc/vision/image_segmenter/calculators/tensors_to_segmentation_calculator.cc)
