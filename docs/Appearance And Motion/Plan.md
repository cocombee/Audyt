# Appearance And Motion Plan

Status: sidebar motion implemented and installed; dark mode deferred.

Reference: [Ikram Sakib’s responsive dashboard animation](https://www.threads.com/@ikramsakib/post/DecTuUWD99H).

## Current authorized motion

AccountingShell owns sidebar width transitions for manual expand/retract and existing automatic responsive transitions. Keep navigation breakpoints, native expand-window behavior, width persistence, route state and divider drag unchanged. Animate width with an interruptible 280ms ease-in/out curve and fade sidebar content over 180ms. Direct divider dragging follows the pointer immediately. Respect reduced-motion preferences. Keep the existing card order, dimensions, column calculation, wrapping and tokens. Continuous sidebar width changes let current page/card owners recompute their existing layouts; no new card arrangement is authorized. Any additional card position tween must reuse its current target geometry and be reviewed separately.

## Future dark mode

Use [wide reference](Dark%20Mode%20Reference%20Wide.png), [narrow reference](Dark%20Mode%20Reference%20Narrow.png) and [intermediate reference](Dark%20Mode%20Reference%20Intermediate.png) as visual inspiration only. Preserve Audyt’s green branding, layout, typography, card structure and accounting flows.

Owner: AccountingTheme and existing semantic color tokens. Build a future light/dark appearance preference at the existing application settings owner; do not create parallel layouts or per-page hardcoded colors. No backend/schema or accounting-data change is needed. Define the preference’s actual persistence adapter during that future implementation.

Acceptance: compare every existing card, table, selector/menu, field, neutral/primary action, alert, badge, document preview and navigation state at wide/narrow sizes; check text contrast, hover/focus/disabled states and vector logos. Keep white PDF pages/documents unchanged. Verify theme switching preserves company, input, route, selection and document state. Dark mode implementation and installation require a later user request.

## Planned smoothing for every card

Requested 14 October 2026. Apply the same 280ms ease-in/out movement and resize timing to every existing card family when its existing responsive owner assigns a new target rectangle. Cover Home metrics/charts/reminders, summaries/report cards, record-list surfaces and other card containers across pages and tabs, including their existing popout card variants. Popout shell geometry remains separate. Do not add cards or change order, row/column membership, wrapping thresholds, spacing, final dimensions, tokens or content. Do not animate tables’ internal cells or transactional line grids as if they were cards.

Prefer native Flutter interpolation under existing layout ownership. Prototype one unchanged responsive card group, then use the verified motion owner across the inventory. Keep card identity stable; interrupt/reverse from its currently visible bounds, preserve focus/input/scroll/selection, respect reduced motion, and keep data refresh independent of animation frames. Verify static before/after geometry against the current layout and movement at intermediate widths; check every card family with long content and high text scaling. No library or React migration is proposed. This is planned work, separate from the sidebar implementation.
