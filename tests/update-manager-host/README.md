# Update manager host regression

Run `tests/run-update-manager-host.ps1` with JDK 17. It compiles the production
`AppUpdateManager` and `UpdatePolicy` against small, isolated Android fixtures.
All HTTPS requests are intercepted in-process; fixtures never contact a server,
download a real APK, invoke Android's installer, or operate an attached device.

The checks exercise server policy changes, cached metadata restoration,
withdrawal during a download, malformed policy, installation revalidation with
changed APK identity, signature rejection/retry, and returning without an actual
package upgrade. The fake main handler drains posted callbacks deterministically.

The `JSONObject` fixture is an object registry rather than a JSON parser. These
tests validate the manager's transitions, not JSON syntax, real DownloadManager
behavior, Android signer APIs, filesystem read-only enforcement, or system UI.
Those boundaries still require the Android SDK compilation/native validation.
