"""Copy profile/chooser marks into the sidebar 20px size/weight family."""
from pathlib import Path
from xml.etree import ElementTree as ET
import json
import pathops
from fontTools.pens.svgPathPen import SVGPathPen
from build_settings_small_icons import geometry

ROOT = Path(__file__).resolve().parents[1]
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
SPECS = {"056-user-outline.svg": (2, False),
         "062-swap.svg": (2, False),
         "089-sign-out.svg": (1.5, True),
         "023-add.svg": (2, True),
         "015-letter.svg": (1.5, False),
         "top-bar-avatar.svg": (1.5, True)}


def main():
    home = ET.parse(ROOT / 'assets/icons/001-home.svg').getroot()
    view = [float(v) for v in home.get('viewBox').split()]
    target = 30 / max(view[2:]) * 20
    metrics = {}
    for name, (thickness, stroked) in SPECS.items():
        source = ROOT / 'assets/icons' / ('reminder_originals' if name == '015-letter.svg' else '') / name
        original = geometry(source, stroked=stroked)
        if stroked:
            original.stroke(thickness, pathops.LineCap.ROUND_CAP,
                            pathops.LineJoin.ROUND_JOIN, 4)
            original.convertConicsToQuads(.0001)
        original = pathops.simplify(original)
        old = original.bounds
        old_view = [float(v) for v in ET.parse(source).getroot().get('viewBox').split()]
        fraction = 1.0  # Sidebar main marks paint their full 20px longest side.
        painted_size = 20 * fraction
        low, high = -thickness * .45, thickness * .3
        for _ in range(40):
            offset = (low + high) / 2
            boundary = pathops.Path(original)
            boundary.stroke(abs(offset) * 2, pathops.LineCap.ROUND_CAP,
                            pathops.LineJoin.ROUND_JOIN, 4)
            boundary.convertConicsToQuads(.0001)
            result = pathops.op(original, boundary,
                                pathops.PathOp.UNION if offset >= 0
                                else pathops.PathOp.DIFFERENCE)
            x0, y0, x1, y1 = result.bounds
            extent = max(x1-x0, y1-y0)
            canvas = extent / fraction
            weight = (thickness + offset * 2) / canvas * 20
            if weight < target:
                low = offset
            else:
                high = offset
        cx, cy = (old_view[0] + old_view[2]/2, old_view[1] + old_view[3]/2)
        pen = SVGPathPen(None)
        result.draw(pen)
        svg = ET.Element(f'{{{NS}}}svg', {'viewBox': f'{cx-canvas/2:.6f} {cy-canvas/2:.6f} {canvas:.6f} {canvas:.6f}'})
        ET.SubElement(svg, f'{{{NS}}}path', {'d': pen.getCommands()})
        ET.ElementTree(svg).write(ROOT / 'assets/icons' / ('profile-' + name), encoding='utf-8', xml_declaration=True)
        metrics[name] = {'source': str(source.relative_to(ROOT)), 'reference': 'assets/icons/001-home.svg',
                         'targetLineWeight': target, 'resultLineWeight': weight,
                         'paintedExtent': painted_size, 'contourOffset': offset}
    (ROOT / 'tool/profile_menu_icon_metrics.json').write_text(json.dumps(metrics, indent=2) + '\n')


if __name__ == '__main__':
    main()
