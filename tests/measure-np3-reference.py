"""Compare independently exported NX neutral/reference images with app point-colour output.

Pillow only. This is an encoded-RGB regression measure, not Delta E, RAW equivalence,
or validation of the shared spatial renderer. All inputs must have equal dimensions.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

parser = argparse.ArgumentParser()
parser.add_argument("folder", type=Path)
args = parser.parse_args()
folder = args.folder
names = ["nx-neutral", "nx-vitality", "nx-nograde", "nx-bright", "app-v3", "app-v4"]
images = {name: Image.open(folder / (name + ".png")).convert("RGB") for name in names}
assert len({image.size for image in images.values()}) == 1
reference = images["nx-vitality"].filter(ImageFilter.GaussianBlur(2))
metrics = {"space": "encoded RGB, 0..255", "size": list(reference.size), "blurRadius": 2,
           "scope": "point-colour approximation on one CC0 RAW exported by NX Studio 1.11; not full Nikon RAW equivalence"}
for name in ["app-v3", "app-v4"]:
    difference = ImageChops.difference(images[name].filter(ImageFilter.GaussianBlur(2)), reference)
    values = ImageStat.Stat(difference).mean
    metrics[name] = {"meanAbsoluteRgb": values, "meanAbsolute": sum(values) / 3}
metrics["inputs"] = {name + ".png": hashlib.sha256((folder / (name + ".png")).read_bytes()).hexdigest() for name in names}
(folder / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
sheet = Image.new("RGB", (1350, 330), "#F8F7F4")
draw = ImageDraw.Draw(sheet)
for i, (name, title) in enumerate([("app-v3", "Huevia before"), ("nx-vitality", "Nikon NX Studio"), ("app-v4", "Huevia 165")]):
    draw.text((450 * i + 12, 9), title, fill="#242320")
    sheet.paste(images[name].resize((450, 300), Image.Resampling.LANCZOS), (450 * i, 30))
sheet.save(folder / "comparison.jpg", quality=94)
print(json.dumps({name: metrics[name]["meanAbsolute"] for name in ["app-v3", "app-v4"]}))
