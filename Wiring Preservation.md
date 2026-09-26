# Wiring preservation

Applies to redesigns and additions: features, tabs, buttons, fields and Settings.

A UI change preserves company/record IDs, application commands, validation,
permissions, revisions, evidence links, persistence and accounting effects.
Labels, icons, order and responsive layout never replace authoritative state.
An enabled new control reaches a real command or route. Disconnected services
remain explicitly unavailable, with no invented save, authentication or delivery.

Before editing, identify the route and shared presentation/service owners. Extend
the actual restored-page and journey tests when adding an operational tab or
control. After the final layout, exercise save, cancel, invalid input, later edits
and applicable transitions, then SQLite reopen/restore and accounting reports.
Verify changed screens at 720 and 1224 with Inter and real icons. Preserve stable
semantic keys; do not test actions solely through presentation text or callbacks.

`tool/check_wiring.sh` runs the analyzer and current route, Settings, reminder,
report, invoice, quotation, restored document and native-file journeys. Run its
synchronized copy in `/private/tmp/AudytBuild` to use the existing native caches.
Extend the gate when more operational flows are introduced. The large-database
and full-suite checks remain separate release checks. A passing gate verifies its
listed cases; future changes still require their own checks. Hosted mail/auth and
installed sandbox acceptance remain separate when unavailable.

Record-row buttons reuse the established small-action assets and frames.
Existing eye-only actions stay icon-only. Eye + Preview text applies to the
original white Review Preview text-button replacement. Callbacks, semantic labels
and data owners remain unchanged when presentation changes.

When View and Preview appear together in a row, View uses the small eye and
Preview uses the small document + magnifier. Preserve distinct action semantics
and callbacks; changing the glyph cannot change which dialog opens.
