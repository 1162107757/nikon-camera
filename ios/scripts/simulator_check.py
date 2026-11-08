import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

app, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
def run(*args): return subprocess.check_output(args, text=True).strip()
available = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j"))["devices"]
candidates = [(runtime, device) for runtime, devices in available.items() if ".iOS-" in runtime for device in devices if device.get("isAvailable") and device["name"].startswith("iPhone")]
assert candidates, "No available iPhone simulator"
runtime, template = sorted(candidates, key=lambda item: tuple(map(int, re.findall(r"\d+", item[0]))), reverse=True)[0]
udid = run("xcrun", "simctl", "create", "Huevia IPA QA", template["deviceTypeIdentifier"], runtime)
records = []
try:
    run("xcrun", "simctl", "boot", udid)
    run("xcrun", "simctl", "bootstatus", udid, "-b")
    run("xcrun", "simctl", "install", udid, str(app))
    for name, argument, appearance, size in [
        ("presets-light", None, "light", "large"),
        ("presets-dark-large", None, "dark", "extra-extra-extra-large"),
        ("camera-light", "--qa-camera", "light", "large"),
        ("settings-light", "--qa-settings", "light", "large"),
        ("preset-detail-light", "--qa-detail", "light", "large"),
    ]:
        subprocess.run(["xcrun", "simctl", "terminate", udid, "cc.huevia.ios"], capture_output=True)
        run("xcrun", "simctl", "ui", udid, "appearance", appearance)
        run("xcrun", "simctl", "ui", udid, "content_size", size)
        args = ["xcrun", "simctl", "launch", udid, "cc.huevia.ios"] + ([argument] if argument else [])
        launched = run(*args)
        pid = int(launched.rsplit(":", 1)[1].strip())
        time.sleep(12 if argument in (None, "--qa-detail") else 3)
        os.kill(pid, 0)
        run("xcrun", "simctl", "io", udid, "screenshot", str(output / (name + ".png")))
        records.append({"screen": name, "processAlive": True, "appearance": appearance, "contentSize": size})
    (output / "simulator-verification.json").write_text(json.dumps({"pass": True, "device": template["name"], "runtime": runtime, "udid": udid, "checks": records, "scope": "Real simulator launch and screenshots; camera hardware and user re-signing not tested"}, indent=2))
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
    subprocess.run(["xcrun", "simctl", "delete", udid], capture_output=True)
