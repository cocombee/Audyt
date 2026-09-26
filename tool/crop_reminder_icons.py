"""Crop only outer transparent space; preserve original artwork byte-for-byte.

Generate bounds first using measure_reminder_crop_test.dart. Original supplied
files remain unchanged. Each derivative changes the root viewBox. Three SVGs
have viewport-relative white mask rectangles: resolve their 100% dimensions
to the original viewBox size so cropping cannot shrink the mask/artwork.
"""
from pathlib import Path
import re
import json

ROOT = Path(__file__).resolve().parents[1]


def cropped(source, bounds):
    tag = re.search(r'<svg\b[^>]*>', source)
    header = tag.group()
    original_box = [float(v) for v in re.search(r'viewBox="([^"]+)"', header).group(1).split()]
    header = re.sub(r'viewBox="[^"]+"',
                    'viewBox="'+' '.join(f'{v:.9f}' for v in bounds)+'"', header)
    body = source[tag.end():]
    for dimension, value in zip(('width', 'height'), original_box[2:]):
        body = body.replace(f'{dimension}="100%"', f'{dimension}="{value:g}"')
    return source[:tag.start()]+header+body


def main():
    bounds = json.loads((ROOT/'tool/reminder_crop_bounds.json').read_text())
    if len(bounds) != 44:
        raise ValueError('The picker must retain exactly the supplied 44 icons')
    output = ROOT/'assets/icons/reminder_cropped'
    output.mkdir(exist_ok=True)
    for name, box in bounds.items():
        source = (ROOT/'assets/icons/reminder_originals'/name).read_bytes().decode('utf-8')
        (output/name).write_bytes(cropped(source, box).encode('utf-8'))


if __name__ == '__main__':
    main()
