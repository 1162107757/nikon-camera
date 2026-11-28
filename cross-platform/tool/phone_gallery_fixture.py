"""Prepare existing app photographs for the Android gallery visual test only."""
import base64
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = root / "app/src/main/assets/preset-showcase"
target = root / "cross-platform/app/integration_test/fixtures/gallery_fixture_bytes.dart"
target.parent.mkdir(parents=True, exist_ok=True)
names = ["sunlit-forest.jpg", "coastal-water.jpg", "rainy-tokyo.jpg", "portrait-smile.jpg", "pink-tulips.jpg", "neon-street.jpg"]
target.write_text("// Existing app photographs; included in the integration APK only.\nconst galleryFixtureBytes = <String, String>" + json.dumps({name: base64.b64encode((source / name).read_bytes()).decode() for name in names}) + ";\n", encoding="utf-8")
print(f"Prepared {len(names)} existing photographs for integration captures.")
