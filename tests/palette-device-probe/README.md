# Palette 126 native probe

Android-only instrumentation for the exact, separately installed production APK. No production classes or private user images are packaged. The runner verifies candidate SHA256 and emulator hardware before any mutation. It saves source/probe provenance and each native result separately by candidate SHA and run ID.

The probe exercises the real white-point touch control while the finger is still down, pointer cancel rollback, internal undo/redo, exact numeric and keyboard controls, strength zero, cancel/apply transactions, the main editor history, draft writes and the currently selected brush region. Native region pixels outside the known synthetic brush support must remain identical. Three modes cover phone, font 1.3 and landscape; screenshots cover five functional states in phone/landscape.

The motion extension checks that the displayed marker follows real DOWN/MOVE coordinates immediately, release feedback settles to zero, reset/undo pass through an intermediate visible position and reach the exact target, and a new touch takes control from a running transition. Dismissal must cancel all motion and prevent later visual changes. Phone adds three native Canvas pad frames around reset; font and landscape only add assertions. A separate `animations-off` mode temporarily disables system animator duration and runs the short static interaction/cancel/apply path. Each runner invocation restores the captured system value in `finally`.

Only a uniquely named synthetic JPEG and its SHA-named private draft are created. Both are removed in the target process after pending saves drain. No user gallery image, network service, camera or publication is used. Settings, app stop and test package cleanup follow the runner's independent finally steps. Remote evidence is retained until the final evidence copy and explicit cleanup are complete.

Build and run only after receiving the frozen candidate identity and exclusive control of the owned emulator from the root agent. Historical failure evidence must remain separate from a corrected final candidate.
