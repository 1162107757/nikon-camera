# Frozen 226 Mac preparation failure — read-only diagnosis

Run `43659369969`, source `0bf8da5d55996aa4aa0e3a70301f37a88f0eba7b`, failed at step 6 **Verify core parity and prepare native runtimes**. No build or test was rerun for this diagnosis. No source, pin, acceptance gate or package was changed.

The actual workflow command was `bash cross-platform/tool/mobile_apple.sh prepare`. The failing nested command is `python3 cross-platform/tool/core_check.py` (`core_ios.sh:16`), specifically the Java runtime invocation in `core_check.py:20`:

```text
$JAVA_HOME/bin/java -Xmx256m -Dfile.encoding=UTF-8 -cp <ROOT>/cross-platform/.build/core-jvm/classes cc.huevia.shared.CoreParity
```

`core_ios.sh:14` selects the configured Java home or Java 21 on macOS. Compilation had already completed; the failure was in JVM assertions, before J2ObjC translation, Flutter tests, UIKit/native integration or IPA acceptance.

The first actual error in the original step log (line 13) is:

```text
java.lang.AssertionError: Live ingest boundary 120
  at cc.huevia.shared.LiveIngestBoundaryTest.yes(LiveIngestBoundaryTest.java:23)
  at cc.huevia.shared.LiveIngestBoundaryTest.rawOriginals(LiveIngestBoundaryTest.java:108)
```

Checkpoint 120 is specifically the second assertion on line 108:

```java
yes(rows(opened,"photos").get(0).get("path").equals(source.toString()));
```

Static call counting proves the exact mapping: 52 checks in the main run before its subroutines + 9 in intent recovery + 20 in large cursor + 27 in no-default originals = 108. RAW checks 109–118 then precede line 108. Check 119 verifies `photoCount==1`; check 120 compares the returned source path literally. Thus the preceding RAW commit count, zero queued count, unchanged NEF bytes and project photo count assertions had already succeeded. This is source analysis, not another runtime execution.

The mismatch follows a fixture/production path-contract difference. The fixture builds `source` beneath a non-canonical `Files.createTempDirectory` path. Production `PhotoLiveProjectStore.java:33,229` canonicalizes its directories and owned source files; `SharedProjects.java:236` returns that canonical photo path. On macOS, a temporary directory spelled under `/var/...` can denote the same file as `/private/var/...`. A literal string comparison against the uncanonical fixture path then fails, while Windows does not exercise that alias. The actual two string values were not printed by this run, so the `/var` spelling is an inference from the exact failing expression and canonical-path contract, not an invented observed value.

The smallest correction is **test-only**: compare line 108's expected path with `source.toFile().getCanonicalPath()`. The same new RAW helper has an analogous later assertion at line 131; its expected `secondSource.toString()` should also use `secondSource.toFile().getCanonicalPath()`. Alternatively canonicalize this fixture's created root once. Keep path equality, photo/task counts, source SHA/bytes, invalid-name and outside-root rejection checks unchanged. Do not change production canonicalization, loosen `equals`, or skip Mac parity. After the fixture correction, rerun the ordinary JVM/full Mac acceptance under a new exact source; this diagnosis does not claim that verification has passed.

Original evidence is preserved locally:

- `workflow-logs.zip`: 20,166 bytes, SHA256 `2e2d9c7b45cc0a14d3c35a3b59d2f3478ecebf052b3d748775fbf2a5e1ad12a1`.
- `workflow-logs/apple-app/6_Verify core parity and prepare native runtimes.txt`: complete 21-line failing step, including the original stack.
- `diagnostic-artifact.zip`: 2,486 bytes, SHA256 `44ee0f90a9ca5790f37f565c8e24f558b29bf31f9ffcdaae2c0d70eb3d543ba6`, exactly matches GitHub's artifact digest. It contains only Flutter bootstrap/version evidence; no passed Flutter/native result or IPA exists in it.
- `frozen-source-evidence.json` and `frozen-source-evidence/`: five exact source blobs read at the failed commit through GitHub GET, with Git blob SHA1 and content SHA256 verified. Later working-tree edits cannot change this diagnosis's source basis.
- `latest-run.json`, `latest-jobs.json`, artifact API/receipts and the download manifest retain source/run provenance.

All network calls were GET-only. The run remains failed and no package is accepted or promoted.
