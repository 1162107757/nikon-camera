# 227 Windows local evidence

This directory preserves existing Windows execution logs and their runners byte for byte. No test, SDK, Git command, API POST or acceptance helper was run for this archive.

Read [local-test-matrix.json](local-test-matrix.json) for qualifications. The initial archive retained nine complete files with real exit0 logs, including the final six-case manual transfer file; later supplements are qualified below. The disconnected-Start group has five final isolated successes; case3 has an earlier isolated success and a later Windows native access violation, so it is not represented as a completed current full-file run. Other native-AV groups retain their actual completed-case counts and remain incomplete.

Real fixture assertion failures, analyzer failures, the temporary diagnostic compile failure and manual cleanup timeout are preserved under `../attempts/windows-*`. The manual fixture eventually passed by observing completion/error flags without re-awaiting the same completed fake-zone Future; product controllers were not changed for that fixture repair. Start fixture fixes wait for route removal and use the correct primary connection button for an invalid session, retaining the original business assertions.

The frozen source recorded at archive time is context, not a claim that every historical log executed after freezing. These logs do not accept an Android/iOS package or replace the same-source full macOS run. No aggregate test total is formed from overlapping and incomplete attempts.

`byte-manifest.json` hashes all copied originals and the archive metadata, excluding the manifest itself. Whole-file qualification is based on both the saved runner exit and the actual `All tests passed`/package-exit0 markers, not merely progress output.

## Privacy fixture follow-up

The old expanded-photo privacy file subsequently completed both tests with real exit0 after a test-only FakeAsync fixture repair. See privacy-final-qualification.json and the byte-exact privacy-final logs, runner and source-input proof. The earlier whole-file AV, Mac720/1timeout, local precache1/1failure and instrumented teardown timeout124 remain historical attempts; none is converted into a pass. The new source is ac5a7ef4ceca2d1b180d6321f683f90241f1234f and the new full macOS run remains a separate acceptance requirement. Original matrix sourceCommitAtArchive remains bf29 context and is not overwritten by this supplement.
