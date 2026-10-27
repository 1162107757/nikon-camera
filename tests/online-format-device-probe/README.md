# Online preset format native probe

Independent instrumentation for the task-owned `emulator-5586` only. The runner requires an explicitly installed, frozen candidate APK and matching SHA-256; it does not install the product, build it, use a physical phone, or publish a release. Networking is disabled while the probe runs and restored afterward. Product request handling uses the incumbent `SecureHttpClient.Connections` seam with in-memory HTTPS responses; no permissive TLS, live catalogue or backend mutation is involved.

Build this probe only after the production candidate is frozen. Then run the phone, large-font, dark, landscape and rail modes individually after exclusive emulator handoff. Each run uses a fresh evidence directory, captures the actual native controls, binds probe and product identities, verifies production sources are stable, uninstalls its own instrumentation and restores emulator settings.

The focused scope checks combined format/category selection, paging resets and stale-response rejection, no-match empty state, local/online return, native control geometry and configuration changes. It does not certify live server catalogue contents, physical-device performance, camera compatibility, TalkBack, frame rate or the APK update policy.
