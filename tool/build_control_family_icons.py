"""Family-scoped contours; retain the original silhouettes and other callers.

Notifications follow the predominant 20px bag mark. New action glyphs follow
the existing supplied Download small-action weight. Original reminder SVGs
and established small-action optical exceptions are never regenerated here.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
import json
import pathops
from fontTools.ttLib import TTFont
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.misc.transform import Transform
from build_settings_small_icons import geometry

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / 'assets/icons'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
NOTIFICATIONS = {
    '003-shopping-bag.svg': (30, False),
    '009-wallet.svg': (30, False),
    '056-user-outline.svg': (2, False),
    '046-voucher.svg': (2, True),
    '006-bank.svg': (30, False),
}
GLYPHS = {
    '090-posted.svg': 0xf134,
    '091-drafts.svg': 0xf05f0,
    '092-clear.svg': 0xf05fa,
    '093-review.svg': 0xf2ea,
    '094-savings.svg': 0xf336,
    '095-sync.svg': 0xe62f,
}


def normalize(shape, thickness, extent, weight, output):
    original = pathops.simplify(shape)
    x0, y0, x1, y1 = original.bounds
    cx, cy = (x0+x1)/2, (y0+y1)/2
    low, high = -thickness*.45, thickness*.45
    unchanged = abs(thickness / max(x1-x0, y1-y0)*extent - weight) < .001
    for _ in range(1 if unchanged else 36):
        offset = (low+high)/2
        edge = pathops.Path(original)
        edge.stroke(abs(offset)*2, pathops.LineCap.ROUND_CAP,
                    pathops.LineJoin.ROUND_JOIN, 4)
        edge.convertConicsToQuads(.0001)
        result = pathops.Path(original) if unchanged or abs(offset) < 1e-7 else pathops.op(
            original, edge, pathops.PathOp.UNION
            if offset >= 0 else pathops.PathOp.DIFFERENCE)
        bounds = result.bounds
        canvas = max(bounds[2]-bounds[0], bounds[3]-bounds[1])
        actual = (thickness+offset*2)/canvas*extent
        if actual < weight:
            low = offset
        else:
            high = offset
    pen = SVGPathPen(None)
    result.draw(pen)
    svg = ET.Element(f'{{{NS}}}svg', {'viewBox':
        f'{cx-canvas/2:.6f} {cy-canvas/2:.6f} {canvas:.6f} {canvas:.6f}'})
    ET.SubElement(svg, f'{{{NS}}}path', {'d': pen.getCommands()})
    ET.ElementTree(svg).write(output, encoding='utf-8', xml_declaration=True)
    return {'paintedExtent': extent, 'lineWeight': actual,
            'contourOffset': offset, 'sourceLineWidth': thickness}


def main(font_path):
    metrics = {'notifications': {}, 'newButtonMembers': {}}
    weight = 30/482*20
    for name, (thickness, stroked) in NOTIFICATIONS.items():
        shape = geometry(ICONS/name, stroked=stroked)
        if stroked:
            shape.stroke(thickness, pathops.LineCap.ROUND_CAP,
                         pathops.LineJoin.ROUND_JOIN, 4)
            shape.convertConicsToQuads(.0001)
        metrics['notifications'][name] = normalize(
            shape, thickness, 20, weight, ICONS/('notification-'+name))
    font = TTFont(font_path)
    glyphs = font.getGlyphSet()
    for name, codepoint in GLYPHS.items():
        shape = pathops.Path()
        glyphs[font.getBestCmap()[codepoint]].draw(
            TransformPen(shape.getPen(), Transform(1, 0, 0, -1, 0, 512)))
        metrics['newButtonMembers'][name] = normalize(
            shape, 43, 14.5, 2/24.0625*14.5, ICONS/'small'/name)
        metrics['newButtonMembers'][name]['codepoint'] = hex(codepoint)
    (ROOT/'tool/control_family_icon_metrics.json').write_text(
        json.dumps(metrics, indent=2)+'\n')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('material_font', type=Path)
    main(parser.parse_args().material_font)
