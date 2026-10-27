# Focused cross-review — version 100

Reviewed on 2026-10-25. No production source was edited and no build, ADB command, physical-device action or remote deployment was run during this review. This is a source review of the requested deletion/navigation and connection boundaries, not a blanket approval of the application.

Candidate APK checked by local SHA-256 only: `dist/huevia-0.21.1-beta-debug.apk`, `6d9c5578071d353e6ee4a3958c5cc0a7ec06383a030474c0d4e98f0be0806860`.

## Finding resolved

The App-only deletion entry previously used the legacy `beforeSavePhotos(Runnable)` overload, which prepares a `PHONE_ALBUM` task. On Android 26–28 this could unnecessarily request `WRITE_EXTERNAL_STORAGE` and block private-file deletion when that permission was refused; Android 33+ could also receive an irrelevant notification-permission request.

Root changed `AlbumPanel.confirmDeleteSelection()` to `host.beforeSavePhotos(PhotoSaveTarget.APP_ONLY, ...)`. Rechecking the call chain confirms that this selects `MainActivity.preparePhotoSave(APP_ONLY, ...)`, skips both `PHONE_ALBUM` permission branches, and still acquires the photo-operation service lease. **The successful runtime-permission path is statically verified only; this review did not run an Android permission dialog, deny/regrant sequence or UI deletion on a device.**

## Deletion and navigation boundaries

- The downloaded-photo entry calls `deleteDownloadedAppCopies`, which passes `false` to `PhotoAlbumDeletion`. Consequently the public-album deletion branch is skipped; no camera API is invoked by this local worker.
- Private-file deletion checks the completed camera-album directory, direct-child ownership, canonical path, symbolic links, JPEG validity, bounded size and content identity. Dependency checks preserve originals or parent effects when a remaining/failed effect needs them. Project references are removed before unlinking. A failure can retain the file while project-reference removal has already committed; the UI reports partial failure and refreshes the remaining files.
- `PhotoLocalTasks.delete()` takes the exclusive reservation synchronously before entering the local queue. Receiving, publication and preset tasks use shared reservations, so they cannot overtake an admitted deletion. Completion, failure and queue rejection release the deletion lease. The application-owned controller also notifies replacement UI observers after settlement.
- The transfer and selection regions use the host navigation inset. `MainActivity` calculates this from the same floating-navigation height used to render the actual navigation: height plus its 14 dp bottom margin on narrow screens, and zero for rail/immersive layouts. The transfer region adds a further 12 dp bottom padding. This resolves the direct tab-bar overlap by construction. Full viewport fit, especially on short displays and large font scales, still depends on native layout verification; source review alone is not a screenshot result.

## Heartbeat and service exit review

- A single application-owned daemon scheduler starts idempotently, admits at most one pending heartbeat, and remains independent of UI-handler dispatch. Album service completion uses the existing serialized album worker; the original UI entry still posts UI callbacks to main.
- A stopped clock cancels future scheduling without interrupting an in-flight PTP transaction. Such an already-running read may legitimately finish and log completion after the stop event. Queued prepared-owner work rechecks the running flag/owner; album generation and ownership are checked by the existing worker before reads.
- Exclusive camera leases suppress extra heartbeats. Temporary complete camera error responses preserve the existing boundary according to the established response policy. Queue rejection clears the pending guard and does not force a healthy connection closed.
- Service creation, idle-stop, timeout and unexpected destruction are separately observable. Unexpected service destruction intentionally retires wireless handles and preserves manual download recovery rather than reconnecting. A photo-processing timeout keeps an active camera service/type. Locks and Wi-Fi demands are released on service exit.
- No new vendor opcode, proactive PTP/IP probe, concurrent camera transaction, automatic reconnection or socket-throughput tuning was introduced.

## Export markers

`REPORT_EXPORT_WRITE_BEGIN`, `REPORT_EXPORT_WRITE_COMPLETE` and `REPORT_EXPORT_WRITE_FAILED` are fixed tokens and do not add URI, filename, network identity or exception messages to the trace. The markers do not close connections or alter ownership. The snapshot includes the begin marker because it is captured afterward. Completion/failure occurs after that snapshot and is therefore visible in a subsequent export/trace, not guaranteed to appear in the JSON currently being written. `WRITE_COMPLETE` records the return of the output write; a later stream-close failure can also produce `WRITE_FAILED`.

## Conclusion and limits

The permission-routing finding is resolved in the reviewed source. No further material issue was found within these requested boundaries. The previously recorded focused host checks remain separate evidence; this review did not rerun them. It does not prove that the user's camera standby/background disconnect is fully resolved, that original wireless throughput improved, or that a system document picker/provider succeeded on the user's phone.

Reviewed production input hashes:

| File | SHA-256 |
| --- | --- |
| `MainActivity.java` | `8f010a2865c11113f775d09525490c2fdfe72a73969b726455002fb1b02424a1` |
| `ui/AlbumPanel.java` | `cc80ef2b351f6b3c870dffe24bec4a6576b6cb28f246986c1113d06ba96b03a2` |
| `album/AlbumController.java` | `962cc34091c7f785c14169eb2c0d0edad9788be36999938561eacf7820bcd0a8` |
| `album/PhotoAlbumDeletion.java` | `2c341873d9165c9602622675d1b0b209e9f9402ec20b878e74a3f739ecd9ea5e` |
| `connection/CameraConnectionRuntime.java` | `c45490c6031aabd64d4a9b8502c61b7d9d672a67971069144e11d5e07bc65d83` |
| `connection/CameraConnectionService.java` | `1fc9384b725761d9d8364e0174f872b4a227f8f076529ec1ae6a5fd8682a4e23` |


## Root follow-up after native layout checks

Final APK SHA: `4ebc35f9fc5930080ba994a6bffe7538feec5bc8679066c698d8f3001b9e37f0`. The subsequent MainActivity-only change computes the navigation inset as the sum of separately rounded navigation height and 14 dp margin, exactly matching the actual LayoutParams. This removes a one-pixel under-reservation at density 2.625; all three final component configurations passed 57 checks each. APP_ONLY deletion and heartbeat/export boundaries are unchanged. The full MainActivity navigation icons are outside the component probe.
