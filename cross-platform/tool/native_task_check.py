#!/usr/bin/env python3
"""Run the Android production task-cancellation boundary without Gradle."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.build_dir or root / "cross-platform" / ".build" / "native-task-jvm"
    output.mkdir(parents=True, exist_ok=True)
    suffix = ".exe" if os.name == "nt" else ""
    java_home = Path(os.environ["JAVA_HOME"]) / "bin" if os.environ.get("JAVA_HOME") else None

    def executable(name):
        candidate = java_home / (name + suffix) if java_home else None
        if candidate and candidate.is_file():
            return str(candidate)
        found = shutil.which(name)
        if not found:
            raise RuntimeError(f"{name} is required for native task boundary checks")
        return found

    source = root / "cross-platform/app/android/app/src/main/java/cc/huevia/sharedapp/NativeTaskCancellation.java"
    test = root / "cross-platform/native/tests/NativeTaskCancellationBoundaryTest.java"
    subprocess.run([executable("javac"), "-encoding", "UTF-8", "-d", str(output), str(source), str(test)], check=True)
    subprocess.run([executable("java"), "-cp", str(output), "cc.huevia.sharedapp.NativeTaskCancellationBoundaryTest"], check=True)


if __name__ == "__main__":
    main()
