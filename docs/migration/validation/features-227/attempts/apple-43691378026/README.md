# Failed 227 Mac full attempt

Source bf29a02bb62babda3caa9ae2a84c5d9454aa3da2, run43691378026, full/macOS26.

The complete Flutter log reports720 passed and1 failed: the old expanded-photo privacy widget timed out after10minutes. The log gives no specific blocked-await stack. All assertions remain in the original fixture; investigation is separate from this immutable attempt.

Core/native preparation and the unsigned device app build succeeded, but those partial successes do not accept the full run. The simulator/UIKit/native/foreground gates were not completed and no IPA was accepted or promoted. Android acceptance is not changed by this archive.

The original GitHub artifact ZIP is preserved and matches its API SHA256 digest. The original workflow-log ZIP, complete API snapshots, full extracted artifact (including Flutter log, native preparation, parity and public-internet receipts) and diagnostic command output are preserved byte for byte. See DIAGNOSIS.json and byte-manifest.json. No SDK, Git command, POST or product mutation was performed during archiving.
