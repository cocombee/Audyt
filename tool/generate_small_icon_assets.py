"""Build Audyt's small-action SVGs.

User-selected assets in user_small_sources are copied unchanged after their
tight crop (and the requested voucher rotation). The remaining legacy assets
retain their existing small-icon treatment. Measure rendered alpha bounds
after changing a source or target mapping.
"""

from pathlib import Path
import json
import shutil
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1] / "assets" / "icons"
OUT = ROOT / "small"
LINE_SOURCES = Path(__file__).resolve().parent / "line_small_sources"
USER_SMALL_SOURCES = Path(__file__).resolve().parent / "user_small_sources"
# These were selected by the user. Their paths, fills and original stroke
# weights are kept; crop_user_small_icons.py only tightens their viewBoxes.
USER_SMALL_ASSETS = {
    "081-nearby-location.svg": "location.svg",
    "078-match-history.svg": "document.svg",
    "079-import-export.svg": "import-export.svg",
    "080-sync.svg": "sync.svg",
    "020-trash.svg": "001-delete.svg",
    "031-image.svg": "002-image.svg",
    "034-controls.svg": "003-equalizer.svg",
    "036-eye.svg": "004-show.svg",
    "037-pencil.svg": "005-edit.svg",
    "038-link.svg": "007-link.svg",
    "040-download.svg": "008-download.svg",
    "041-checklist.svg": "009-checklist.svg",
    "044-invoice.svg": "010-invoice.svg",
    "045-expense.svg": "011-account.svg",
    "046-voucher.svg": "coupon.svg",
    "042-history.svg": "013-history.svg",
    "051-restore.svg": "014-history-1.svg",
    "043-receive.svg": "015-receive-mail.svg",
    "053-pie-outline.svg": "016-stats.svg",
    "054-bar-outline.svg": "017-bar-chart.svg",
    "056-user-outline.svg": "018-user.svg",
    "059-list-outline.svg": "019-list.svg",
    "066-money.svg": "020-money.svg",
    "065-money-bag.svg": "021-money-bag.svg",
    "067-month-clock.svg": "022-30-days.svg",
    "074-year-calendar.svg": "023-calendar.svg",
    "075-account-grouping.svg": "stock-market.svg",
    "061-more-horizontal.svg": "024-menu.svg",
    "052-receive-money.svg": "dollar.svg",
    "069-category-outline.svg": "030-menu-1.svg",
    "071-cash-register.svg": "028-cash-register.svg",
    "072-preview.svg": "031-preview.svg",
    "073-six-month-calendar.svg": "026-6 month.svg",
    "064-quarter-calendar.svg": "027-quarter.svg",
}
# Keep the geometry-locked stacked coins and balance paths untouched.
PRESERVE_SOURCE_GEOMETRY = {
    "068-coins.svg",
    "070-balance-thin.svg",
}
# Small icons are an independent visual group; changing this value does not
# change main/sidebar or navigation artwork.
SMALL_ICON_STROKE_PX = 1.0
LINE_SOURCE_BASE_STROKE_PX = 1.25
# Navigation controls form their own family. The current 18px chevron's
# 2/24 source stroke is a 1.5px screen stroke, independent of action icons.
NAVIGATION_STROKE_PX = 1.5
NAVIGATION_ASSETS = {
    "025-chevron-right.svg",
    "026-chevron-left.svg",
    "027-chevron-down.svg",
}
SMALL_PAINTED_SIDE_PX = 13.5
FILLED_STROKE_FRACTION = 0.032
FILLED_STROKE_OVERRIDES = {
    "007-calendar.svg": 0.020,
    "009-wallet.svg": 0.050,
    "032-warning-sign.svg": 0.0,
    "033-info.svg": 0.0,
    "035-error.svg": 0.0,
    "054-bar-outline.svg": 0.0,
    "056-user-outline.svg": 0.0,
    "059-list-outline.svg": 0.0,
    "060-coin-outline.svg": 0.020,
    "064-quarter-calendar.svg": 0.010,
}
SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")


def inherited(element, parents, key, default=None):
    for node in (element, *reversed(parents)):
        if key in node.attrib:
            return node.attrib[key]
    return default


def adjust(element, parents, source_stroke_width, filled_stroke_width):
    tag = element.tag.rsplit("}", 1)[-1]
    if "stroke-width" in element.attrib:
        element.set("stroke-width", f"{source_stroke_width:.6f}")
    if tag in {"path", "circle", "ellipse", "rect", "line", "polyline", "polygon"}:
        stroke = inherited(element, parents, "stroke", "none")
        fill = inherited(element, parents, "fill", "black")
        if stroke != "none":
            if inherited(element, parents, "stroke-width") is None:
                element.set("stroke-width", f"{source_stroke_width:.6f}")
        elif fill != "none" and filled_stroke_width > 0:
            element.set("stroke", "#000000")
            element.set("stroke-width", f"{filled_stroke_width:.6f}")
            element.set("stroke-linejoin", "round")
            element.set("stroke-linecap", "round")
    for child in element:
        adjust(child, (*parents, element), source_stroke_width, filled_stroke_width)


def main():
    OUT.mkdir(exist_ok=True)
    painted_fractions = json.loads(
        (Path(__file__).parent / "icon_source_metrics.json").read_text()
    )
    for source in sorted(ROOT.glob("*.svg")):
        if source.name == "016-document.svg" or source.name.startswith(("profile-", "notification-")):
            # Shared replacement is generated from its original filled folder.
            continue
        if source.name not in painted_fractions:
            raise ValueError(f"Measure the painted bounds of {source.name} first")
        if source.name in USER_SMALL_ASSETS:
            shutil.copyfile(USER_SMALL_SOURCES / USER_SMALL_ASSETS[source.name], OUT / source.name)
            continue
        if source.name in PRESERVE_SOURCE_GEOMETRY:
            shutil.copyfile(source, OUT / source.name)
            continue
        line_source = LINE_SOURCES / source.name
        if line_source.exists():
            tree = ET.parse(line_source)
            root = tree.getroot()
            scale = SMALL_ICON_STROKE_PX / LINE_SOURCE_BASE_STROKE_PX
            for element in root.iter():
                width = element.attrib.get("stroke-width")
                if width is not None:
                    element.set("stroke-width", f"{float(width) * scale:.6f}")
            tree.write(OUT / source.name, encoding="utf-8", xml_declaration=True)
            continue
        tree = ET.parse(source)
        root = tree.getroot()
        viewbox = root.attrib.get("viewBox")
        if not viewbox:
            raise ValueError(f"{source.name} has no viewBox")
        longest = max(float(value) for value in viewbox.replace(",", " ").split()[2:])
        fraction = painted_fractions[source.name]
        target_stroke = (
            NAVIGATION_STROKE_PX
            if source.name in NAVIGATION_ASSETS
            else SMALL_ICON_STROKE_PX
        )
        source_stroke_width = target_stroke * longest * fraction / SMALL_PAINTED_SIDE_PX
        filled_fraction = FILLED_STROKE_OVERRIDES.get(source.name, FILLED_STROKE_FRACTION)
        adjust(root, (), source_stroke_width, longest * filled_fraction)
        tree.write(OUT / source.name, encoding="utf-8", xml_declaration=True)
    for target, source in USER_SMALL_ASSETS.items():
        if not (ROOT / target).exists():
            shutil.copyfile(USER_SMALL_SOURCES / source, OUT / target)
    # These two Banking-only variants have user-requested contour weights.
    # Keep the originals and all unrelated small-icon treatments unchanged.
    for source in (Path(__file__).parent / "menu_small_sources").glob("*.svg"):
        shutil.copyfile(source, OUT / source.name)
    from build_document_file_icon import main as build_document
    build_document()
    from build_profile_menu_icons import main as build_profile
    build_profile()


if __name__ == "__main__":
    main()
