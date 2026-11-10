"""Fail closed if the artifact is a simulator bundle or lacks a real ARM64 executable."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

path = Path(sys.argv[1])
with zipfile.ZipFile(path) as archive:
    assert archive.testzip() is None, "IPA ZIP CRC failed"
    info = plistlib.loads(archive.read("Payload/Huevia.app/Info.plist"))
    assert info["CFBundleIdentifier"] == "cc.huevia.ios"
    assert info["CFBundlePackageType"] == "APPL"
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Simulator build cannot be signed for an iPhone"
    executable = archive.read("Payload/Huevia.app/" + info["CFBundleExecutable"])
    magic, cpu, subtype, filetype, commands, commandbytes, flags, reserved = struct.unpack_from("<8I", executable)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C and filetype == 2, "Expected a thin ARM64 Mach-O executable"
    cursor = 32
    platforms = []
    signed = False
    for _ in range(commands):
        command, size = struct.unpack_from("<II", executable, cursor)
        assert size >= 8 and cursor + size <= len(executable)
        if command == 0x32:
            platforms.append(struct.unpack_from("<I", executable, cursor + 8)[0])
        if command == 0x1D:
            signed = True
        cursor += size
    assert platforms == [2], f"Expected iOS device platform, got {platforms}"
    assert "Payload/Huevia.app/embedded.mobileprovision" not in archive.namelist()
    assert not any(n.startswith("Payload/Huevia.app/_CodeSignature/") for n in archive.namelist())
    for name in ["alpine-lake", "breakfast", "city-skyline", "coastal-water", "neon-street", "pink-tulips", "portrait-man", "portrait-smile", "rainy-tokyo", "sunlit-forest"]:
        photo = archive.read("Payload/Huevia.app/" + name + ".jpg")
        assert len(photo) > 1024 and photo[:2] == bytes([0xFF, 0xD8]), "Missing bundled reference JPEG"
print(json.dumps({"pass": True, "bundleIdentifier": info["CFBundleIdentifier"], "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"], "minimumOS": info["MinimumOSVersion"], "platform": "iPhoneOS", "architecture": "arm64",
    "machOSignatureCommandPresent": signed, "provisioningProfilePresent": False, "requiresUserSigning": True,
    "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}, indent=2))
