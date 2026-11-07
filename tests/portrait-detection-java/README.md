# Portrait detection geometry regression

Run `run.ps1` with JDK17 and the real Android API35 `android.jar`. It compiles the production `PhotoPortraitDetection` and `PhotoPortrait` classes and reflects into their pure geometry helpers. Android bitmap, Canvas and native FaceDetector stubs are never executed on the host JVM, and no detector/model implementation is copied into this test.

Coverage includes two-scale spatial/eye-distance/roll boundaries and angular wrap, optional legacy three-field anchors, one-to-one nearest assignment and input order, preserving multiple real faces, conservative duplicate merging, smaller-eye-distance merge radius, symmetric duplicate decisions, immutable inputs, malformed/non-finite/non-positive anchor rejection, explicit cancellation and thread interruption.

This is a geometry regression, not photographic face-detection accuracy evidence. Native image detection, transformations, real public positive/negative samples and private local user-image reproduction must be checked separately. No user photograph is stored in this suite.
