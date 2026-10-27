# Connection and original transfer analysis — 2026-10-25

This analysis reads the user's exported 0.21.0-beta report locally. Only fixed event names, operation codes, connection ordinals, relative intervals and numeric transfer measurements are reproduced. The report itself is not copied into the repository; camera identities, network addresses, UUIDs and photograph metadata are omitted.

## Observed report evidence

- The first recorded `UI_BACKGROUND` is followed by an already-running series of `0x90c4` large-thumbnail reads. The last read fails after 3,567 ms with the fixed `IO` category. `PTP_CLOSED` follows in the same millisecond, approximately 9,276 ms after the background event.
- The matching Wi-Fi loss arrives approximately 2,887 ms after PTP closure. This sequence does not show Wi-Fi loss initiating that first PTP closure. The old report cannot distinguish a command socket failure from an event socket failure with a concurrent read; the new channel events address this gap.
- On the next connection, one complete `0x1009` original contains **12,853,156 bytes**. The transaction lasts **111,032 ms**, approximately **0.116 MB/s** using decimal MB.
- Of that transaction, instrumented payload reads consume **110,465 ms**, destination writes **77 ms**, and progress callbacks **78 ms**. There are **0** read timeouts. The remaining transaction time includes framing and response processing. This puts the measured delay in incoming payload reads rather than local file writes or progress callbacks. It does not distinguish the camera, Wi-Fi radio/link or Android TCP/network behavior.
- Private-original save begins after that transaction and completes **261 ms** later.
- The final event is another `UI_BACKGROUND`. A report captured before opening/completing the system document picker cannot contain future connection events after its own snapshot. Therefore this report alone cannot identify the second reported disconnect.
- The user's observation that the camera display was black is relevant but does not prove whether only its display, its standby timer or the Wi-Fi subsystem was asleep.

## Code review and bounded improvement

`MainActivity.onPause()` detaches UI work and releases comparison views, without closing the application-owned camera session. The connected-device service already owns the CPU lock, Wi-Fi demand and runtime. The old ten-second heartbeat was scheduled on the main `Handler`; its album completion was also posted to that handler. UI stalls could postpone both the scheduling and the reset of the single pending-heartbeat guard.

The updated runtime has one service-owned daemon clock, with an immediate first check and a three-second interval. Album service completion runs on the existing camera worker instead of waiting for main delivery. The normal UI API preserves main-thread callbacks. PTP remains strictly serialized on the existing album worker; at most one heartbeat is pending, exclusive camera work suppresses heartbeats, and stopping the clock never interrupts an in-flight PTP read. This is a keepalive improvement; the report does **not** prove that a delayed main loop caused the user's disconnect.

New bounded diagnostics record service create/idle stop/unexpected destroy/timeout, acquired or unavailable locks, heartbeat queued/completed/failed, and command-versus-event channel failures. Routine heartbeat events share the existing ten-second disk batch, while failures retain the existing urgent path. The 256-event/64 KiB limits and fixed-token/numeric-only schema remain in force.

No new Nikon vendor command, proactive PTP/IP probe, capture action, reconnect loop or socket throughput parameter was added. In particular, `0x90c8` is Nikon DeviceReady, not evidence of a Nikon camera-sleep-prevention command. Android 14+ low-latency Wi-Fi locks also have screen/foreground restrictions, so these locks alone cannot promise background retention; the existing service-owned `NetworkRequest` remains necessary. Sources: [libgphoto2 PTP operation definitions](https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/ptp.h), [Android WifiManager reference](https://developer.android.com/reference/android/net/wifi/WifiManager).

## Focused verification

- `tests/run-album.ps1 -HeartbeatOnly`: **10 checks passed** using the actual controller and framed synthetic PTP sockets. Two service heartbeats finish while UI dispatch is paused; the original UI callback stays deferred; a heartbeat waits behind an in-flight GetObject without interleaving or retransferring; a complete DeviceBusy response preserves the same session for the following successful heartbeat.
- `tests/run-wifi-runtime.ps1`: **29 checks passed**, including the previous Wi-Fi loss boundaries and the new actual service clock completing three heartbeats while the test UI Handler never drains, idempotent start, stopped-clock suppression, one-pending bound and exclusive-versus-local work behavior.
- `tests/run-ptpip-download.ps1`: **5,043 checks passed**, including original byte integrity, timeouts, ownership, cancellation, and command/event failure-origin logging without private strings.

These are host tests and a local report analysis. They do not establish real camera standby prevention, OEM background survival or improved real wireless throughput. No physical camera or phone was operated by this work.
