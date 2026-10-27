# Android update core review

Date: 2026-10-25, Asia/Shanghai.

This is a summary of commands and results already confirmed in tool outputs,
not a saved raw execution log. Tests were not repeated just to produce this
record. No production APK was built by this reviewer; no attached device, real
HTTP endpoint, APK download, installer, release upload, or publication was used.

## Inputs

The final production inputs include the default-channel follow-up described
below. Read-only inspection after the final focused tests confirmed these hashes;
the reviewer made no subsequent production edits.

| Input | SHA-256 |
| --- | --- |
| `app/src/main/java/cc/huevia/updates/AppUpdateManager.java` | `5adaf18dfd3d12e36846f72cf023ef5abf00ccb5bccd23f69b607fc06b9cd840` |
| `app/src/main/java/cc/huevia/updates/UpdatePolicy.java` | `45c2ae490d4052347abbf70e0ccec506cda7c2aad6717f31f5ea09f8494fe68c` |

## Executed checks

Commands were run from `D:/dev/ai-project/nikon` with JDK
`D:/dev/Java/jdk-17.0.19` through a context-mode child-process wrapper.

| Command | Confirmed outcome | Approximate execution time |
| --- | --- | --- |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run-updates.ps1` | `Update policy: 66 checks passed (host-only).` Exit 0. | 2026-10-25 07:00 CST |
| JDK `javac.exe --release 17 -encoding UTF-8 -cp D:/dev/android-sdk/platforms/android-35/android.jar -d .tooling/update-core-99/classes app/src/main/java/cc/huevia/updates/AppUpdateManager.java app/src/main/java/cc/huevia/updates/UpdatePolicy.java` | Exit 0; standard deprecated API note only. | 2026-10-25 07:00 CST |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run-update-manager-host.ps1` | `App update manager: 37 checks passed (offline host fixtures; no device/real HTTP/APK install).` Exit 0. | 2026-10-25 07:00 CST |

Execution times above are approximate, derived from generated class-file
timestamps rather than timestamped raw stdout. The relevant artifact times were
`2026-10-24T23:00:24.259Z` for `UpdatePolicyTest.class`,
`2026-10-24T23:00:27.072Z` for `AppUpdateManagerHostTest.class`, and
`2026-10-24T23:00:28.433Z` for the SDK-compiled `AppUpdateManager.class`.

The 66 policy assertions cover existing URL/hash/package/minimum SDK/progress
boundaries and the new mandatory/default/type/installed-version and automatic
check timing and default channel rules. The 37 manager assertions execute the production manager
against offline Android and HTTP object fixtures, including persisted metadata
restoration, mandatory withdrawal during download, failed checks, queued checks
during verification, unchanged APK policy updates, same-ID changed hashes,
withdrawal before installation, signature failure/retry, and returning without
an actual package upgrade.

The manager harness replaces Android framework services and uses a JSONObject
object registry rather than a JSON parser. Its passing result does not establish
real JSON parsing, DownloadManager behavior, Android signing APIs, package
installation, Wi-Fi performance, or system UI. See
`tests/update-manager-host/README.md` for the boundary.

## Default-channel follow-up

Root review found that a beta installation with no saved channel preference
always queried stable metadata, which could miss later beta releases. The final
manager now infers beta only when the installed `PackageInfo.versionName`
contains `-beta` (case-insensitive); otherwise it infers stable. Explicit stable
or beta preferences retain priority. Inference does not write a preference or
force a user who selected stable onto beta.

New host cases verify beta with no preference, beta with explicit stable,
stable with no preference, stable with explicit beta, and no persisted write
for inferred channels. Pure policy cases additionally cover case-insensitive
beta markers and unknown version-name fallback. Tests were rerun because the
production behavior changed, not merely to create this record.

The earlier successful 62-policy / 32-manager runs were performed at approximately
06:50 / 06:53 CST on these pre-follow-up inputs:

| Input | Earlier SHA-256 |
| --- | --- |
| `AppUpdateManager.java` | `8500a7e36ed6ec5271ec6ba12a2cde7f1a2e7535ae5267b9bc9bf2ff33bed349` |
| `UpdatePolicy.java` | `6d89d8d53c73908fa70639fab2a7e32278dbe8cc46d90f257d6b13093e4cd1ec` |

Those earlier counts are historical evidence and are not added to the final
66 / 37 counts as if they were distinct assertions on the final inputs.

## Earlier fixture cleanup failure and residual files

The initial manager run reached 29 passing assertions, then failed in its
`finally` cleanup with `java.nio.file.AccessDeniedException`. This run had exit 1
and is not counted as a successful test run. Production `verify()` calls
`safe.setReadOnly()`; because the harness uses real host files, that made the
internal fake APK read-only on Windows. The harness cleanup was corrected to
restore writability on its own files before deletion. The later successful
32-assertion run completed cleanup and exited 0.

The initial failed run left these two **24-byte fake APK fixture files**. Both
contain the literal text `offline apk-byte fixture`; neither is an installable
APK or user photo.

1. `C:/Users/11621/AppData/Local/Temp/huevia-update-manager-host-11740343299106923468/install/internal/app-updates/d2658cbb34369d3982b13215bf0be868484f15cb0f7efc5d3531aaaa756657f8.apk`
   — Windows attributes `33` (`ReadOnly | Archive`).
2. `C:/Users/11621/AppData/Local/Temp/huevia-update-manager-host-11740343299106923468/policy/external/app-updates/d2658cbb34369d3982b13215bf0be868484f15cb0f7efc5d3531aaaa756657f8.apk`
   — Windows attributes `32` (`Archive`).

Two cleanup attempts were rejected before execution by the command tool:

- A PowerShell command checked the resolved absolute fixture root, cleared
  read-only attributes inside that root, then requested recursive removal of
  that root.
- A narrower PowerShell command listed only the two complete file paths with
  `-LiteralPath`, then the known empty directories in child-to-parent order;
  this command did not use `-Recurse`.

Both returned `rejected: blocked by policy`; no more specific reason was
provided. Neither command executed. The reviewer stopped cleanup attempts and
did not bypass the rejection through another tool. The root agent was given the
exact paths and attributes for its assessment; this record does not claim those
two residual files were removed.

## UI read-only review

The reviewer also inspected the root agent's `UpdatePanel` changes without
editing them. No concrete blocking defect was found in the reviewed mandatory
non-cancelable prompt, same-APK policy switch, ordinary eight-hour prompt
suppression, foreground pump, pause/resume, installation epoch, or unknown-source
permission return paths. This was a source review, not Android component or
system installer verification.
