"""Settings-only contour variants; retain original and other small artwork.

Existing small controls are reused by AccountingSettingsIcon. Only marks
without an established small caller get a Settings variant. The supplied
small Download is their physical-weight reference; contours are not redrawn.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
import json
import math
import re
from copy import deepcopy
import pathops
from fontTools.svgLib.path import SVGPath
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.misc.transform import Identity, Transform

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / 'assets/icons'
OUT = ICONS / 'small'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
EXTENT = 14.5
WEIGHT = 2 / 24.0625 * EXTENT
# Explicit Settings optical corrections: dense marks follow the thinner peers.
THINNER_MARKS = {'002-office.svg', '005-calculator.svg', '006-bank.svg',
                 '019-bill.svg', '016-document.svg', '015-police.svg'}
# Existing straight outline thickness in each source's coordinate system.
SPECS = {
    '002-office.svg': (ICONS, 2, False),
    '005-calculator.svg': (ICONS, 1.5, False),
    '006-bank.svg': (ICONS, 30, False),
    '019-bill.svg': (ICONS, 2, False),
    '003-shopping-bag.svg': (ICONS, 30, False),
    '016-document.svg': (ICONS, 1.5, False),
    '021-upload.svg': (ICONS, 2, True),
    '013-bell.svg': (ICONS, 32, False),
    '004-tax.svg': (ICONS, 2, False),
    '015-police.svg': (ICONS, 2, False),
}

def geometry(source, stroked=False):
    shape = pathops.Path()
    def visit(node, parent):
        transform = Identity
        for operation, raw in re.findall(r'(\w+)\(([^)]*)\)', node.get('transform','')):
            values = [float(x) for x in re.split(r'[\s,]+',raw.strip())]
            if operation == 'matrix': part = Transform(*values)
            elif operation == 'translate': part = Identity.translate(values[0],values[1] if len(values)>1 else 0)
            elif operation == 'scale': part = Identity.scale(values[0],values[1] if len(values)>1 else values[0])
            elif operation == 'rotate':
                cx,cy = values[1:] if len(values)>1 else (0,0)
                part = Identity.translate(cx,cy).rotate(math.radians(values[0])).translate(-cx,-cy)
            else: raise ValueError(operation)
            transform = transform.transform(part)
        transform = parent.transform(transform)
        if node.tag.rsplit('}',1)[-1] in {'path','circle','ellipse','rect','line','polyline','polygon'}:
            copy = deepcopy(node)
            copy.attrib.pop('transform',None)
            root = ET.Element(f'{{{NS}}}svg')
            root.append(copy)
            part = pathops.Path()
            SVGPath.fromstring(ET.tostring(root)).draw(TransformPen(part.getPen(),transform))
            if not stroked:
                if node.get('fill-rule') == 'evenodd':
                    part.fillType = pathops.FillType.EVEN_ODD
                part = pathops.simplify(part)
            shape.addPath(part)
        for child in node: visit(child,transform)
    visit(ET.parse(source).getroot(),Identity)
    return shape

def main():
    metrics = {}
    for name, (directory, thickness, stroked) in SPECS.items():
        if name == '016-document.svg':
            # Its user-supplied folder replacement owns all three variants.
            continue
        source = directory / name
        target_weight = WEIGHT * (.9 if name in THINNER_MARKS else 1)
        shape = geometry(source, stroked=stroked)
        if stroked:
            shape.stroke(thickness, pathops.LineCap.ROUND_CAP,
                         pathops.LineJoin.ROUND_JOIN, 4)
            shape.convertConicsToQuads(0.0001)
        shape = pathops.simplify(shape)
        original_bounds = shape.bounds
        original_extent = max(original_bounds[2]-original_bounds[0], original_bounds[3]-original_bounds[1])
        lo, hi = -thickness * .35, thickness * .65
        for _ in range(36):
            offset = (lo+hi)/2
            boundary = pathops.Path(shape)
            boundary.stroke(abs(offset)*2, pathops.LineCap.ROUND_CAP,
                            pathops.LineJoin.ROUND_JOIN, 4)
            boundary.convertConicsToQuads(.0001)
            result = pathops.op(shape, boundary,
                pathops.PathOp.UNION if offset >= 0 else pathops.PathOp.DIFFERENCE)
            x0,y0,x1,y1 = result.bounds
            extent = max(x1-x0,y1-y0)
            padding = extent/2048
            weight = (thickness+offset*2)/(extent+padding*2)*EXTENT
            if weight < target_weight: lo = offset
            else: hi = offset
        pen = SVGPathPen(None)
        result.draw(pen)
        svg = ET.Element(f'{{{NS}}}svg', {'viewBox':f'{x0-padding:.6f} {y0-padding:.6f} {x1-x0+padding*2:.6f} {y1-y0+padding*2:.6f}'})
        ET.SubElement(svg,f'{{{NS}}}path',{'d':pen.getCommands()})
        ET.ElementTree(svg).write(OUT/('settings-'+name),encoding='utf-8',xml_declaration=True)
        metrics[name] = {'source':str(source.relative_to(ROOT)),'paintedExtent':EXTENT,
            'referenceLineWeight':WEIGHT,'targetLineWeight':target_weight,'sourceLineWidth':thickness,'offset':offset,
            'resultLineWeight':weight,'originalExtent':original_extent}
    (ROOT/'tool/settings_small_icon_metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
    from build_document_file_icon import main as build_document
    build_document()

if __name__ == '__main__': main()
