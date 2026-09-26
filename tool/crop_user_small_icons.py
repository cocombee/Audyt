"""Crop user-supplied small SVGs without changing their paths or stroke weight.

Bounds in user_small_icon_bounds.json were measured from each SVG rendered at
2048px, including visible antialiasing plus a two-pixel safety margin.
"""

import json
from pathlib import Path
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "user_icon_originals"
OUTPUT = ROOT / "user_small_sources"
BOUNDS = ROOT / "user_small_icon_bounds.json"
SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")


def number(value: float) -> str:
    return f"{value:.6f}".rstrip("0").rstrip(".")


def main() -> None:
    OUTPUT.mkdir(exist_ok=True)
    bounds = json.loads(BOUNDS.read_text())
    for filename, (x, y, width, height) in bounds.items():
        tree = ET.parse(SOURCE / filename)
        root = tree.getroot()
        root.attrib.pop("width", None)
        root.attrib.pop("height", None)
        if filename in {"012-coupon.svg", "coupon.svg", "refund.svg"}:
            # Rotate the user-selected artwork clockwise, keeping paths intact.
            original_children = list(root)
            for child in original_children:
                root.remove(child)
            group = ET.SubElement(
                root,
                f"{{{SVG_NS}}}g",
                {
                    "transform": (
                        f"translate({number(height)} 0) rotate(90) "
                        f"translate({number(-x)} {number(-y)})"
                    )
                },
            )
            group.extend(original_children)
            root.set("viewBox", f"0 0 {number(height)} {number(width)}")
        else:
            root.set(
                "viewBox",
                f"{number(x)} {number(y)} {number(width)} {number(height)}",
            )
        tree.write(OUTPUT / filename, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
