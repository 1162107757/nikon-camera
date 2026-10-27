# Native update component attempts

All runs below use production candidate `523bd07fb93bd7c1cea3ce8cb5bc451b91fe53ded2355a926dff559b0b61aaec`, version code 99. Each run preserves its original `provenance.json`, `cleanup.json`, instrumentation output and nested report/screenshots. No failed report was rewritten to pass.

| Run | Result | Explanation |
| --- | --- | --- |
| `20261025-070425-font-1-0-aec82e` | Failed setup, 7 checks | The probe initially supplied a 13,672,454-byte fixture, exceeding the production 4 MiB APK limit. The real `Release` constructor rejected it before any prompt. The fixture was corrected to the actual candidate size, 3,901,562 bytes; production validation was unchanged. |
| `20261025-070505-font-1-0-172e74` | Failed assertion, 131 checks and 2 screenshots | The probe read the scroll position immediately after native smooth `fullScroll`, before the animation completed. The probe was corrected to disable smooth scrolling for this test and perform the same actual `fullScroll`, then assert the real bottom position. Full text layout, no ellipsis and button reachability thresholds were retained. |
| `20261025-070534-font-1-0-9a4363` | Passed, 244 checks and 5 screenshots | Final normal font configuration. |
| `20261025-070543-font-1-3-445cd7` | Passed, 245 checks and 5 screenshots | Final Activity-local 1.3 font configuration. |

A host preflight SHA-parser error occurred before installing or launching the probe and produced no Android run. Its PowerShell grouping was corrected before the first recorded instrumentation run. Build setup also required PowerShell 7, as used by the project; these harness setup issues are not application defects.

Both final runs use the same probe APK and installed production APK identities, listed in their provenance files. The 489 checks are repeated component assertions across two font configurations, not 489 unique end-to-end scenarios. All 10 final screenshots were individually viewed. The probe uses actual production `UpdatePanel`, `Release`, `AppUpdateManager` and native Android dialog classes, with synthetic validated release/status callbacks. The replacement Activity prevents `MainActivity.onCreate`; its background and insets are test-host presentation, not approval of the full app layout.

No metadata HTTP, DownloadManager, APK download, unknown-source permission, package installer, camera, account or physical device was exercised. Retry/download/install/exit buttons were not activated; the stale withdrawn download button reference was activated and rejected by the real handler with zero manager worker tasks. Progress and failure displays are injected state coverage, not evidence of an actual download. All recorded runs restored update preferences, removed their owned fixture and uninstalled the probe. `emulator-5586` was left running and handed back to the root task.
