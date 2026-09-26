"""Build only the shared document/file symbol from the supplied folder.

Keep the supplied filled silhouette; contour it to the physical thickness of
the established main, small-action and thinner Settings document variants.
The original reminder icon chooser remains a separate artwork collection.
Requires the existing Audyt Icon Tools pathops/fontTools runtime.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
import json
import pathops
from fontTools.pens.svgPathPen import SVGPathPen

from build_settings_small_icons import geometry

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tool/user_icon_originals/folder.svg"
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)

# Each target retains its existing caller size and physical line weight.
SPECS = {
    "assets/icons/016-document.svg": (20, 1.5 / 21.515625 * 20),
    "assets/icons/small/016-document.svg": (14.5, 2.1885 / 21.515625 * 14.5),
    "assets/icons/small/settings-016-document.svg": (14.5, 1.0846753246753247),
}


def main():
    original = geometry(SOURCE)
    metrics = {}
    for name, (size, target) in SPECS.items():
        low, high = -10.0, 15.0
        for _ in range(40):
            offset = (low + high) / 2
            boundary = pathops.Path(original)
            boundary.stroke(abs(offset) * 2, pathops.LineCap.BUTT_CAP,
                            pathops.LineJoin.MITER_JOIN, 4)
            boundary.convertConicsToQuads(.0001)
            result = pathops.op(original, boundary,
                                pathops.PathOp.UNION if offset >= 0
                                else pathops.PathOp.DIFFERENCE)
            x0, y0, x1, y1 = result.bounds
            extent = max(x1 - x0, y1 - y0)
            padding = extent / 2048
            weight = (30 + offset * 2) / (extent + padding * 2) * size
            if weight < target:
                low = offset
            else:
                high = offset
        pen = SVGPathPen(None)
        result.draw(pen)
        svg = ET.Element(f"{{{NS}}}svg", {
            "viewBox": f"{x0-padding:.6f} {y0-padding:.6f} {x1-x0+padding*2:.6f} {y1-y0+padding*2:.6f}",
        })
        ET.SubElement(svg, f"{{{NS}}}path", {"d": pen.getCommands()})
        ET.ElementTree(svg).write(ROOT / name, encoding="utf-8", xml_declaration=True)
        metrics[name] = {"source": str(SOURCE.relative_to(ROOT)),
                         "paintedExtent": size, "targetLineWeight": target,
                         "resultLineWeight": weight, "contourOffset": offset,
                         "sourceLineWidth": 30, "paintedBounds": [x0, y0, x1, y1]}
    (ROOT / "tool/document_file_icon_metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")


if __name__ == "__main__":
    main()
