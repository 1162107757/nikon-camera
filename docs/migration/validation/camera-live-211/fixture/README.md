# 211 A1 controlled PTP/IP peer

This is an owned synthetic protocol fixture. It is not physical Nikon/Fuji/iPhone acceptance and contains no real sensor RAW. JPEG pixels are generated locally with Pillow. NEF entries have synthetic metadata only and cannot be downloaded.

Start from the project directory:

    python .tooling/cross-platform187/camera211_peer.py run1

The emulator camera address is `10.0.2.2`, port `15750`. The host control server binds only `127.0.0.1:15751`. A run tag cannot overwrite an existing `211-peer-<tag>-operations.jsonl`. Stop with Ctrl+C; shutdown records `211-peer-<tag>-summary.json`. Starting the peer preserves no runtime objects from another process: use the same running peer to test a dropped connection and reconnect, rather than restarting it.

Initial old inventory: JPEG handles 1 and 2; synthetic NEF 101. The stable nonzero GUID is `211a102030405060708090a0b0c0d0e0`; reconnecting to the same process keeps it. There are two storage slots; slot 2 starts empty and available.

Read `GET http://127.0.0.1:15751/status`. Send JSON to `POST /action`, for example with Python urllib or PowerShell Invoke-RestMethod.

| JSON | Effect |
| --- | --- |
| `{"action":"add"}` | Add the next JPEG and send one ObjectAdded notification. |
| `{"action":"add-many","count":3,"duplicates":3}` | Add a burst and send three notifications per object. |
| `{"action":"add","event":false}` | Add without an event; periodic directory reconciliation must find it. |
| `{"action":"event","handle":3,"duplicates":5}` | Resend duplicate or stale notifications. |
| `{"action":"add","readyAfterSeconds":5,"pending":"busy"}` | List an object immediately; GetObjectInfo returns DeviceBusy until ready. |
| `{"action":"add","readyAfterSeconds":5,"pending":"zero"}` | Metadata exists with zero compressed size until ready. |
| `{"action":"mutate","handle":3}` | Reuse the handle with a new descriptor/content identity; original local bytes must stay unchanged. |
| `{"action":"remove","handle":3}` | Remove from the directory; subsequent access returns InvalidObjectHandle. |
| `{"action":"fault","handle":3,"afterBytes":16384,"once":true}` | Break both channels during the next original transfer; the next reconnect may complete. |
| `{"action":"fault","handle":3,"clear":true}` | Remove a persistent injected fault. |
| `{"action":"drop"}` | Drop currently connected channels; the listener remains ready to accept reconnect. |
| `{"action":"storage","storage":2,"available":false}` | Slot 2 returns StoreNotAvailable. Add with storage 2, then restore; its first accessible inventory is old baseline. |
| `{"action":"pacing","delaySeconds":0.25,"chunkBytes":8192}` | Slow the original transfer for UI progress/stop checks. |
| `{"action":"inventory-mode","allReturnsRawOnly":true}` | Unfiltered inventory returns only synthetic RAW; JPEG format queries remain valid. |

Add accepts handle, storage, raw, extraBytes (0..2MiB), readyAfterSeconds (0..120), pending, event, and duplicates. The fixture is bounded to 1000 objects. Add-many is bounded to 30 objects per action. A baseline object must not produce an automatic GetObject merely from enabling the run.

Status includes object metadata SHA, expected original SHA/bytes, attempted/completed original downloads per handle, command operation counts, command/event connection IDs and notifications delivered. Only an explicit valid original read increments download attempts. An injected partial disconnect does not increment completed downloads.

Record these observations separately in the app: no old-baseline download; burst and missing-event discovery; duplicate notifications do not duplicate imports/rendered versions; unfinished metadata waits; reused handles revalidate; dropped partial originals are not imported; reconnect catches unfinished/new objects; stopped or owner-changed work cannot commit late results. This peer does not prove project journal atomicity or lifecycle behavior.

Bounded self test on ephemeral ports, with automatic shutdown:

    python .tooling/cross-platform187/camera211_peer.py --self-test

A separate bounded conformance probe uses the already compiled original PtpIpClient from the core JVM output, compiles only a small private Java probe, and starts temporary loopback servers:

    python .tooling/cross-platform187/211-peer-probe.py

Its result is saved in 211-peer-java-probe.log. It confirms the actual original client parses the fixture device, receives duplicate wire events, reads exact JPEG bytes, handles DeviceBusy without closing, and reconnects after an interrupted read. It does not exercise SharedCamera A1 discovery, the project journal or Flutter UI.

The wire event is PTP/IP type 8 with a 10-byte payload: uint16 code 0x4002, uint32 transaction, uint32 handle. This matches original PtpIpClient lines 756-769. Callbacks enqueue work only; periodic inventory handles missed events. This fixture has no camera-write API.
