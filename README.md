# audyt

Local-first accounting for every included accounting workflow.

## macOS package verification

Build the canonical debug bundle and verify its signed entitlements with:

```sh
flutter build macos --debug
./tool/verify_macos_package.sh
```

The verification command checks the bundle signature and requires both the app sandbox and `com.apple.security.files.user-selected.read-write` entitlement. Pass another `.app` path as the first argument to verify that bundle instead.

For a release build, use an Apple-issued identity and preserve Xcode-expanded entitlements before staging or installing it:

```sh
flutter build macos --release
AUDYT_SIGNING_IDENTITY="Apple Development: Your Name (identity suffix)" ./tool/sign_macos_package.sh
```

The signing script also runs package verification. Do not re-sign `Audyt.app` without its release entitlements: doing so prevents the native document picker from opening.

## Bank statement reconciliation

Audyt retains imported bank statements as evidence and keeps their rows separate from posted accounting entries. Maybank PDF imports validate the printed holder, account, date, and running balances, and detect duplicate statements. The import preview separates incoming and outgoing transaction types and preserves each row's original narrative and source page.

An unconnected row remains a Banking review item. Automatic connection is limited to one unambiguous posted outgoing movement on the linked account with matching amount, nearby date, and independent reference evidence. Incoming receipts, partial payments, and deposits need manual allocation. The review view shows the connected journal and lets a reviewer retract an incorrect connection with a reason, refresh candidates, and connect another posted movement. An approved reconciliation must be reopened before its connections change. Saving a draft from a bank row does not connect it or approve the statement; the movement must be posted and matched, and reconciliation approval is a separate balance-and-evidence step.

The Banking screen keeps statement actions and the connection-status filter outside the transaction card. Each row has its own link-review action beside the amount, and the Rows selector and pagination remain inside the shared list card. The screen shows the selected statement's connected and unconnected rows, identifies each connected journal movement, and lets the user switch statements, inspect the preserved source, or save that source to a chosen location. Inflow/outflow classification is internal matching data, not a user-facing filter. The account summary shows balance, connection, and approval as separate cards while all three fit. At the responsive break, it keeps balance and connection; approval remains visible on each statement row.

The match review shows the number of statement rows still unconnected, each bank row beside its suggested posted-ledger candidates, and the linked journal plus a reasoned retraction action after acceptance. Reconciliation pre-fills dates from imported rows (or the PDF statement period where available), pairs start/end dates and opening/closing balances, and shows remaining rows and a zero-balance target alongside its difference checks. Approval still requires the full domain review; a zero count alone is insufficient.

Audyt's View and Edit actions use accessible eye and pencil icons in the shared square side-action frame. Their painted stroke and frame match the delete control; longer workflow actions keep text labels.

When adding an icon, first identify the rendered family it is joining and compare its visible size, stroke weight, and alignment with that family's existing icons. Reusing an SVG or glyph from another family does not carry its old scale or treatment into the new one. Coloured Home metric/reminder boxes, small row actions, notification icons, sidebar/profile icons, and bare empty-state icons have separate baselines. The Home Recent Expenses empty state uses a neutral 20px outlined receipt glyph, not the coloured icon-box artwork. Keep its accessible label and verify the rendered result at the supported minimum width before accepting a new family member.

The [Zoho Books banking and reconciliation walkthrough](https://www.youtube.com/watch?v=cdYXmpLQpYE) provided workflow reference: matching links an existing posted record, while categorizing creates a record; import preview distinguishes ready, erroneous, and unmapped lines; and review can filter incoming and outgoing activity. Its deposit-slip example (23:18–25:09) combines several recorded cash receipts through an undeposited-funds deposit into one bank movement. Audyt must preserve the separate receipts and match the bank's consolidated credit to a separately posted aggregate deposit, rather than treating one receipt as the whole bank amount. That grouped deposit posting and multi-allocation model is not implemented yet; consolidated credits remain for manual review. Rules that merely recognize a likely category should stay distinct from rules that post accounting entries automatically, and incoming customer payments must not be silently classified as new sales.


## Google sign-in and update safety

The macOS client is configured for Google project `cocombee-audyt`. Google identity is separate from local profile labels and future business membership; signing in does not grant accounting roles. Credentials are managed by the native Google SDK in Keychain. The initial Director is to be established through verified membership, not a client-side email comparison.

Builds need an Apple development provisioning profile for `com.cocombees.audyt`. Do not replace the installed app with an unsigned/ad-hoc workaround. Development signing is for local testing, not public distribution.

Before every installed update:
- Preserve the bundle ID, native database-path contract, preference keys and security-scoped folder bookmarks.
- Take a consistent SQLite backup (SQLite backup API, including committed WAL state), plus a preference/bookmark snapshot, outside the app bundle. Do not copy only a live SQLite main file.
- Record schema version, integrity/foreign-key checks, row counts and content fingerprints, and document-link/blob metadata. Test required migrations against a copy first.
- Preserve original document bytes and their linked locations. Never reset app data, clear preferences, regenerate workspace identity, or silently replace an unreadable database.
- After replacement, compare the database and saved settings; verify existing linked-document access and saved folder permissions in the installed app. Signing/container changes need actual runtime verification. Restore the previous app if checks fail; keep the data backup until verification passes.
- Do not treat Demo Company fixtures as evidence of durable live data. Local Google sign-out must not delete accounting records, documents, settings or filing permissions.
