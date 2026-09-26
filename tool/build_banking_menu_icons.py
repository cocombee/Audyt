"""Build only the user-requested Banking menu contour variants.

Requires fonttools and skia-pathops. Preserve originals and every existing
small asset. The old 051-restore.svg (not its location replacement) is the
physical line-weight reference. Contours change thickness around the original
filled boundaries; they do not redraw or estimate a new centerline.
"""

from pathlib import Path
import json
import xml.etree.ElementTree as ET

import pathops
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.svgLib.path import parse_path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tool/menu_small_sources"
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
BASELINE = 14.5
REFERENCE = 1.5 / 17.554688 * BASELINE


def geometry(filename):
    root = ET.parse(filename).getroot()
    shape = pathops.Path()
    for element in root.iter():
        if element.tag == f"{{{NS}}}path":
            parse_path(element.attrib["d"], shape.getPen())
    return shape


def contour(shape, amount):
    boundary = pathops.Path(shape)
    boundary.stroke(abs(amount) * 2, pathops.LineCap.ROUND_CAP,
                    pathops.LineJoin.ROUND_JOIN, 4)
    boundary.convertConicsToQuads(0.0001)
    return pathops.op(shape, boundary,
                      pathops.PathOp.UNION if amount > 0 else pathops.PathOp.DIFFERENCE)


def write_variant(source, target, outward):
    shape = geometry(source)
    # Original straight sections in both supplied silhouettes are 2 units.
    # Account for changed painted extent as the contour grows or shrinks.
    lo, hi = (0, 1) if outward else (-0.5, 0)
    for _ in range(35):
        amount = (lo + hi) / 2
        result = contour(shape, amount)
        x0, y0, x1, y1 = result.bounds
        extent = max(x1 - x0, y1 - y0)
        padding = extent * 2 / 2048
        line_px = (2 + amount * 2) / (extent + padding * 2) * BASELINE
        if line_px < REFERENCE:
            lo = amount
        else:
            hi = amount
    pen = SVGPathPen(None)
    result.draw(pen)
    svg = ET.Element(f"{{{NS}}}svg", {
        "viewBox": f"{x0-padding:.6f} {y0-padding:.6f} {x1-x0+2*padding:.6f} {y1-y0+2*padding:.6f}",
    })
    ET.SubElement(svg, f"{{{NS}}}path", {"d": pen.getCommands()})
    ET.ElementTree(svg).write(OUT / target, encoding="utf-8", xml_declaration=True)
    return {"source": str(source.relative_to(ROOT)), "contourSourceUnits": amount,
            "paintedSidePx": BASELINE, "straightLineWeightPx": line_px}


def main():
    OUT.mkdir(exist_ok=True)
    variants = {
        "080-sync.svg": write_variant(ROOT / "tool/user_icon_originals/sync.svg", "080-sync.svg", False),
        "082-banking-setting.svg": write_variant(ROOT / "assets/icons/small/017-setting.svg", "082-banking-setting.svg", True),
        "086-change-account-normalized.svg": write_variant(ROOT / "assets/icons/small/076-change-account.svg", "086-change-account-normalized.svg", False),
    }
    (OUT / "metrics.json").write_text(json.dumps({
        "reference": "assets/icons/small/051-restore.svg",
        "referenceLineWeightPx": REFERENCE, "variants": variants,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
