# Offline portrait inference dependencies

This app bundles the standalone Java Interpreter runtime from Google's
`com.google.ai.edge.litert:litert:1.4.1` and `litert-api:1.4.1` artifacts.
`LICENSE-LiteRT.txt` is copied intact from the official runtime AAR and includes
Apache-2.0 and the bundled third-party notices.

Only `face_landmarks_detector.tflite` is extracted from the official Google
MediaPipe Face Landmarker float16/version-1 model bundle. Its embedded metadata
identifies it as “Face mesh detection model v2”, version 1, author MediaPipe,
with 478 landmarks. The official Face Mesh V2 model card identifies the model
license as Apache-2.0 and its authors as Geng Yan and Ivan Grishchenko (Google).
`LICENSE-MediaPipe.txt` preserves the upstream MediaPipe repository license;
the source page and model card are retained below.

- Model guide: https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker
- Model card: https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MediaPipe%20Face%20Mesh%20V2.pdf
- Bundle: https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
- Upstream license: https://github.com/google-ai-edge/mediapipe/blob/v0.10.32/LICENSE

The semantic face-skin model is Google's official **Selfie Multiclass 256x256,
float32/version 1** model, by Adel Ahmadyan (Google), dated May 10, 2023. The
official Multiclass Segmentation model card explicitly identifies its license
as Apache License, Version 2.0; the complete upstream Apache-2.0 license is
preserved in `LICENSE-MediaPipe.txt`.

- Model guide: https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter
- Model card: https://storage.googleapis.com/mediapipe-assets/Model%20Card%20Multiclass%20Segmentation.pdf
- Original model: https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite

The original model has 16,371,837 bytes and SHA-256
`c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0`.
It is stored as `portrait/face_skin_multiclass.shuffle4.zlib` to fit the universal
APK without changing its weights or any model metadata. This is a reversible
byte-storage transform, followed by .NET 10 `ZLibStream` with `SmallestSize`:
let `N = floor(16371837 / 4) = 4092959`; byte plane `p` contains the original
bytes at offsets `4*i+p`, for `p=0..3` and `i=0..N-1`. The final one trailing byte
is appended unchanged. There is no custom header. The zlib stream is 13,881,786
bytes, SHA-256
`9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0`;
APK ZIP storage leaves this already compressed asset uncompressed.

`FaceSkinModel` restores the four planes directly into a native-order direct
buffer through a 64 KiB `InflaterInputStream`, verifies exact compressed and
decoded lengths and both hashes, and caches only a verified read-only model.
Cancellation and failures never populate the cache. Its `decode(InputStream,
BooleanSupplier)` method leaves input-stream ownership with its caller, while
`load(Context, BooleanSupplier)` opens and closes only the bundled asset. No
photographs are model preparation inputs, and no model or image is uploaded.

Semantic input is FLOAT32 `[1,256,256,3]`, RGB normalized as `RGB/127.5-1`.
Its single FLOAT32 `[1,256,256,6]` output contains raw logits in label order
`background`, `hair`, `body-skin`, `face-skin`, `clothes`, `others`. Apply stable
softmax once across the six values at each pixel to obtain probabilities;
subtract the maximum logit before exponentiating. Its embedded
`SEGMENTER_METADATA` (`V001`) sets activation to `SOFTMAX` (enum 2), which the
official MediaPipe Image Segmenter graph applies after inference. The model's
own output producer is a CONV_2D operator. The internal attention Softmax
operators do not normalize this final output.

- Official activation lookup: https://github.com/google-ai-edge/mediapipe/blob/v0.10.32/mediapipe/tasks/cc/vision/image_segmenter/image_segmenter_graph.cc
- Official stable-softmax postprocessing: https://github.com/google-ai-edge/mediapipe/blob/v0.10.32/mediapipe/tasks/cc/vision/image_segmenter/calculators/tensors_to_segmentation_calculator.cc

Face-skin is class 3. The model uses only standard LiteRT operators. Its model
card notes that segmentation is not pixel-perfect and quality can degrade with
large occlusions; source attribution does not assert per-image accuracy.

The MediaPipe Tasks SDK, Play Services runtime, Google data-transport libraries,
GPU delegate and blendshape model are not included. The app loads the bundled
model into its own CPU Interpreter; model preparation and fixed dependencies
are build-time operations, not downloads triggered by a photograph.

Run `scripts/prepare-face-landmarks.ps1` before a direct Gradle build. The manual
APK build invokes it automatically. Official downloaded artifacts are cached in
`.tooling/face-landmarks-cache`; valid cached bytes are reused without network
requests. Downloads and extracted model/JAR bytes are SHA-256 pinned, all four
ABI libraries are checked for 16 KiB ELF LOAD alignment, and all generated
outputs are recorded in `BUILD-IDENTITY.json`. The semantic packing identity is
also pinned, so a different encoder that produces different bytes fails the
preparation step instead of silently changing the distributed artifact.
