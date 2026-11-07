from pathlib import Path
from PIL import Image, PngImagePlugin
import base64, json

here = Path(__file__).resolve().parent
source = here.parents[0] / 'photo-detail-export-histogram-20261024' / 'assets' / 'sample.png'
image = Image.open(source).convert('RGB')
# A portrait demonstration photograph, derived from an existing project sample.
w, h = image.size
crop = image.crop((0, 0, int(h * .8), h)).resize((800, 1000), Image.Resampling.LANCZOS)
crop.save(here / 'assets' / 'portrait.jpg', quality=94)
encoded = base64.b64encode((here / 'assets' / 'portrait.jpg').read_bytes()).decode()
(here / 'photo.js').write_text('window.PROTOTYPE_PHOTO = "data:image/jpeg;base64,' + encoded + '";\n', encoding='utf-8')
(here / 'assets' / 'provenance.json').write_text(json.dumps({
    'portrait.jpg': {'origin': str(source), 'use': 'Existing illustrative project sample, cropped to 4:5 for this prototype only; not a camera output or an AI retouch claim.'},
    'reference-prisma.png': {'origin': 'https://cdn.dribbble.com/userupload/37212909/file/original-0b2f84c71e9f2a2a1be52509f95e653f.png', 'author': 'Daria Bugrowskaia / Prisma Labs', 'use': 'Reference inspection only; not displayed in the prototype.'}
}, ensure_ascii=False, indent=2), encoding='utf-8')
print('Prepared 800 x 1000 sample photograph and offline image data.')
