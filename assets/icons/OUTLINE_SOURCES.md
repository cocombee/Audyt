The outline controls in this group were copied as SVG through the project's licensed Flaticon account. The paths are unchanged; only empty editor groups and SVG metadata were removed. Existing user-supplied icons were not replaced.

| Local asset | Flaticon source |
| --- | --- |
| `053-pie-outline.svg` | https://www.flaticon.com/free-icon/pie-chart_535282 |
| `054-bar-outline.svg` | https://www.flaticon.com/free-icon/bar-chart_2152675 |
| `055-refresh-outline.svg` | https://www.flaticon.com/free-icon/refresh_2805355 |
| `056-user-outline.svg` | https://www.flaticon.com/free-icon/user_2805403 |
| `057-zoom-in-outline.svg` | https://www.flaticon.com/free-icon/zoom-in_2805419 |
| `058-zoom-out-outline.svg` | https://www.flaticon.com/free-icon/zoom-out_2805425 |
| `059-list-outline.svg` | https://www.flaticon.com/free-icon/list_2805320 |
| `060-coin-outline.svg` | https://www.flaticon.com/free-icon/coin_2529396 |

The main-size assets above retain their licensed source geometry. Several small-button variants have since been replaced by user-selected SVGs; see below.

`062-swap.svg` and `063-google.svg` are the exact Flaticon SVGs supplied by the user for the profile menu. The swap source is https://www.flaticon.com/free-icon/swap_7133490.

The current small chart controls use the user's quarter (`027-quarter.svg`), six-month (`026-6 month.svg`), year (`023-calendar.svg`), month (`022-30-days.svg`), money-bag (`021-money-bag.svg`), money (`020-money.svg`), cash-register (`028-cash-register.svg`), and By Account (`stock-market.svg`) designs. The older List icon remains reserved for List. The stacked-coins (`068-coins.svg`) design remains archived but is no longer the Direct Costs control.

In Banking match review, the document-search (`072-preview.svg`), history arrow (`051-restore.svg`) and history-with-list (`042-history.svg`) are existing user-supplied small icon-only artwork. Their button boxes stay 32px.

## Small icon-only buttons

The latest user-selected SVG originals are in `tool/user_icon_originals/`. Run `python3 tool/crop_user_small_icons.py` to reproduce their tight viewBoxes in `tool/user_small_sources/`, then `python3 tool/generate_small_icon_assets.py` to install the mapped small assets. Cropping does not edit path data, fill, or stroke. Voucher uses the later `coupon.svg`, rotated 90° so its longest side is vertical. The earlier `012-coupon.svg` and `refund.svg` remain as unused originals. Active card/chart/row small marks and opened More-menu action marks have a 14.5px painted-longest-side baseline. Eye, Create Invoice, Money Bag, Cash Register, and By Account are +1px; Pen and Category are −1px, preserved relative to any future baseline change and removed only when that icon artwork is replaced. Receive Money uses the replacement `dollar.svg` at the standard 14.5px size. Help, Close, alerts, navigation, and other excluded controls retain their own sizing. These user-selected replacements retain their differing original optical stroke weights; do not add a contour or normalize them to the legacy 1px line family. Their app color comes from `AccountingIcon` or the chart control's color filter.

The remaining small controls still use the legacy line drawings in `tool/line_small_sources/` or the main SVGs. The warning, info, and error variants retain their source fill without an extra contour. The stacked-coins (`068`) source is copied byte-for-byte. General View uses `004-show.svg`; Review Posting and Review Statement Connections use `031-preview.svg`. Attachment View uses the image/file icon, including the new supplied image glyph in its More menu. The supplied clock (`025-clock.svg`) is kept as an original pending a destination. Image-edit controls are outside this replacement batch. Banking uses the original slash-through-link geometry with a matched small stroke for row actions and the user's newer broken-link artwork for the green summary-card info icon.

The alert bell uses the same `013-bell.svg` as the sidebar/main icon family at a 20px painted longest side, matching its roughly 1.25px optical stroke and foreground color. The avatar is a true-stroke rendering of its original user silhouette; the sidebar compactor keeps its 17px size with the same on-screen weight. Navigation chevrons are audited separately at their original 18px, 2/24-stroke reference, about 1.5px on screen. Do not put the compactor, bell or avatar in the chevron family.

`070-balance-thin.svg` is Google's Material Symbols outlined balance icon at weight 300, from https://github.com/google/material-design-icons/blob/master/symbols/web/balance/materialsymbolsoutlined/balance_wght300_24px.svg. It replaces the heavier Material Icons font glyph only for Audyt's labelled Reconciliation buttons. Its 17px canvas paints about 13.5px wide with a roughly 1.06px vertical stroke, matching the adjacent Imported folder's visual size while reducing the scale's heavy base and pans.

`069-category-outline.svg` and its small line source now align the lower-right triangle's apex and base center with the upper-right circle. The original small drawing centered the circle at x=18 but the triangle at x=17, which made the triangle look shifted left. The regular version also had mismatched right-column centers and an unrounded lower-left square.
