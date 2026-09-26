# Audyt membership service

Implementation in progress. The six-table initial schema is created in the dedicated cocombee_audyt database and remains empty. The PHP service is privately staged but has no active public endpoint. The installed app has an opt-in connection implementation; its real service/business binding is not configured.

Current staging: the previous service package is extracted in the private Audyt Service folder on hosting. Configuration has no database password; there is no public endpoint or active backup schedule. This is staging, not deployment. Local MariaDB 10.11.19 integration now passes 50 checks, including independent-process revision races and encrypted backup/restore. These results do not prove hosting behavior.

Target: existing NameHero Business Cloud cPanel, PHP 8.3 and MariaDB 10.11. Keep a dedicated Audyt database, restricted database user, and separate document root. Do not modify existing site roots, databases, DNS records or account-wide PHP settings. No new paid hosting.

`src/MembershipPolicy.php` owns authorization and state transitions. Its inputs must come from a database transaction after Google token verification, never from client-supplied actor roles. Lock the business row before reading memberships so concurrent Director changes serialize. Apply the entire returned batch, audit and idempotency receipt in that transaction.

Implemented locally: membership policy, transactional command/directory repository, schema, input validation, Google verifier wrapper, bounded HTTPS entrypoint, shared rate limiting and encrypted membership backup/restore. Fifty-two integration checks pass on disposable MariaDB 10.11.19 using fictional users; cryptographic verification uses ephemeral test keys and controlled certificate fixtures. The Flutter connection and foreground notification adapter are implemented behind explicit configuration. Remaining: actual hosting runtime/database/TLS checks, private configuration, dedicated public origin, verified Master Director linking and real installed end-to-end tests. The temporary local PHP CLI is a test tool, not the hosting deployment runtime.

## File storage boundary

Transaction originals and image/PDF derivatives remain in the user's configured local folders (or explicitly selected Drive destination). This membership database has no document binary columns and this service must expose no transaction-file upload endpoint. Do not upload the SQLite ledger, security-scoped bookmarks, device-local paths, or receipt bytes during sign-in or registration.

Future device coordination may carry portable document IDs, checksums, revisions and delivery status. A mobile device retains an original until the owning destination device confirms matching bytes at the intended location. Unreachable destinations remain pending. Hosted coordination is not proof of local filing, and cross-device transport is not implemented here.

## Migration safety

`migrations/001_membership.sql` is an initial schema for an empty Audyt-only database. It is not an upgrade script for any website database. It intentionally has no DROP statements, cascading deletes or live bootstrap inserts. The runtime should have only the required SELECT/INSERT/UPDATE permissions on its dedicated tables; audit history has no delete operation. The schema and restricted runtime permissions were tested on disposable local MariaDB; actual hosting behavior still requires verification.

## Directory reads

`MembershipRepository::directory` rechecks the verified actor’s current approved Director membership under the same business lock used by writers. It returns bounded pages, an unfiltered total for the more-than-ten search threshold, filtered count, and pending registration count. Revoked memberships remain in audit storage but disappear from the directory. Literal name/email searches escape SQL wildcard characters. Google subject and verified login email are not included in directory results. Local MariaDB authorization, pagination, literal-search and competing-revision integration checks pass; these do not substitute for actual hosting verification.

## Google verification (not yet deployed)

`GoogleIdentityVerifier` delegates cryptographic verification to the official `google/auth` AccessToken verifier with a server-configured audience. `VerifiedGoogleClaims` applies additional audience/issuer/expiry/issued-at/verified-email/subject checks and emits no role or access grants. Never call the claims helper directly on decoded client input.

Composer dependencies are installed and pinned in `composer.lock` (google/auth 1.55.0, firebase/php-jwt 7.2.0, phpseclib 3.0.57). `composer audit --locked` reported no vulnerability advisories on 26 September 2026. `GoogleIdentityVerifier::forHosting` now composes a bounded HTTPS client and private persistent certificate cache. Hosting configuration and verification remain required.

Local checks: 15 policy, 12 command input, 11 registration input, 11 claim, 12 certificate transport and 14 cryptographic integration checks pass. The signature tests generate ephemeral RSA keys and exercise the actual Google/Firebase libraries with mocked certificate delivery: valid identity without role leakage, wrong audience/issuer, expiry, future issue time, unverified email, missing subject, tampered payload, wrong signing key, HMAC substitution, malformed/oversized input, certificate reuse and safe network-failure reporting. They do not prove live Google networking or hosted MariaDB behavior.

The temporary macOS CLI uses `OPENSSL_CONF=/etc/ssl/openssl.cnf` for test key generation. Its dependency installation ignores only the locally absent ext-curl; production still requires ext-curl and must pass an unmodified Composer platform check. Do not deploy this incomplete service.

## Certificate transport

`GoogleCertificateTransport` accepts only Google’s fixed HTTPS GET certificate endpoint, verifies TLS, refuses redirects, applies connection/read/total timeouts and limits responses to 64 KiB. Provide a private mode-0700 cache directory outside the public root. Mode-0600 cache files are atomically replaced and expire within Google’s remaining max-age, capped at one hour. Expired cache is never served during an outage. A real HTTPS request from the local runtime returned HTTP 200 and two public keys without sending any user token. Hosting networking still needs verification.

## API boundary (local, not deployed)

`MembershipApi` handles versioned business-scoped self, registration, directory, notification and command routes. It verifies a bearer token, resolves the current membership by verified Google subject, and never accepts caller ID or caller role from request JSON. Repository commands repeat authority checks under the business lock. Bodies are bounded to 64 KiB, JSON depth to eight, unknown fields rejected, methods constrained, and internal failures reduced to safe error codes. Eighteen isolated API checks pass; store doubles do not prove MariaDB behavior.

The HTTP entrypoint, HTTPS enforcement, file-backed rate limiter and private configuration template now exist locally. Private database credentials, real-server configuration and deployment are still pending. Do not publish this folder wholesale: vendor, source, configuration and caches belong outside the public root.

## HTTP runtime and limits (not deployed)

`public/index.php` refuses non-HTTPS requests, emits no-store JSON responses, restricts POST bodies to JSON, reads at most 64 KiB plus one overflow byte and returns generic failures. `config.local.php`, dependencies and source stay above the document root. Only `public/` may be served. Apache rewrite configuration preserves bearer authorization. Verify this on the actual host before activation, including TLS, authorization-header forwarding, rate-limit responses and denial of private-file URLs.

`RequestRateLimiter` stores only HMAC-derived client identifiers in a private mode-0600 file. It allows 60 requests per peer IP per minute and 600 globally, with a fixed minute window; both limits apply across PHP workers. Busy/corrupt/unavailable state fails closed. Seventy local checks pass, including worker reuse, expiry, global exhaustion, private permissions and raw-IP absence. This is a single-host application limit, not upstream DDoS protection; shared-network capacity and boundary bursts need deployment testing. It trusts REMOTE_ADDR only. Review actual proxy topology before changing that policy.

## Automatic private backup (implemented locally, not scheduled)

`bin/backup.php` is CLI-only. It reads private server configuration and takes one repeatable-read snapshot of the supported dedicated schema. Version 1 covers the six membership tables; version 2 includes all fourteen tables after authentication migration 002. Exact table and column contracts prevent a future migration from silently omitting new data. It encrypts the snapshot with AES-256-GCM and a fresh nonce, writes an owner-only temporary file, checks its SHA-256 and decrypts it before atomic publication. Archive versions are authenticated by the encryption context. One private lock prevents overlapping jobs. Keep the last 14 successful daily snapshots; malformed names, unrelated files and symlinks are not retention targets. Failures emit only a timestamp and `backup_failed`, return a nonzero exit code and leave older snapshots intact.

Before activation, provision `var/backups` mode 0700 above all web roots; add `backupKey` (base64 of 32 random bytes) privately to `config.local.php` mode 0600. Retain a recoverable copy of that key separately from the archives. An archive alone cannot be restored if the key is lost. The job requires PHP 8.3 CLI with PDO MySQL and OpenSSL. Verify the actual CLI path, timezone, permissions, daily schedule and failure monitoring on hosting before creating the cPanel cron entry. Do not alter any website's existing backups or account-wide settings.

Version-2 snapshots contain account identities, password hashes, email/verification/session digests, terms acceptance, permissions, rate-limit state, audit and encrypted security-mail intents. Treat the archive as sensitive even though it is encrypted. No raw passwords/session tokens, Google ID tokens, database passwords, image/PDF/document bytes, local paths or device bookmarks enter it. Accounting sync and portable document/folder connection tables are not implemented, so they cannot be backed up here yet. A later explicit Drive/local backup adapter will manage the second copy; it is not activated by Google sign-in.

Recovery requires a precreated empty matching Audyt schema and a maintenance window with HTTP requests, mail workers and backup jobs stopped. Version 1 restores into migration 001; version 2 requires migrations 001 and 002. The single migration-created auth guard row is retained and locked first. `MembershipBackup::restoreEmpty` validates the archive, locks empty table ranges, inserts rows transactionally and refuses an existing dataset. It retains identities, password hashes, Google links, terms acceptance, permissions and existing audit. Version 2 invalidates every restored active session and unconsumed challenge, cancels queued mail and clears its payload, and records one recovery event in the same transaction. Users sign in again and request fresh codes; stale queued security messages are not resent. Historical accepted/cancelled mail and earlier revocations remain intact. There is no public restore endpoint or automated overwrite of a live database.

Retain `backupKey` and the original `authenticationKey` in separate protected recovery storage outside the archives. The authentication key is required to resolve email keys and verify the keyed password hashes; restoring rows alone does not recreate that configuration. Keep `mailEncryptionKey` and the remaining restricted operator configuration available for the service's mail transport. Test recovery with those exact keys before activation. Recovery restores the selected snapshot's point in time: password or permission changes made after it are not magically recovered. Reconcile later revocations/role changes and require password recovery where compromise is suspected before reopening service. Confirm operator identity, backup age, schema, company/owner bindings, login, roles, audit, private-file denial and actual host behavior. Never overwrite a live service to rehearse recovery.

Local evidence: 20 archive checks (tampering, wrong key, unsupported content, private files); 10 isolated cron-entrypoint checks (retention, lock, symlinks, safe failure); 52 MariaDB checks (including exact restore and overwrite refusal). Run `tests/mariadb_integration.php` only with the private JSON configuration for a new disposable `audyt_test_<12 hex>` loopback database. It refuses other DSNs and nonempty schemas. Root credentials are fixture-only; the service path exercises a SELECT/INSERT/UPDATE-only test user.

## Director capability context

The authenticated self-membership response includes `masterDirectorId` only for an approved Director, resolved from the business’s bound bootstrap row. Clients use it to disable protected removal/demotion and self-access controls; it never authorizes a command. The repository repeats the existing membership and Master protections under its transaction lock. Older responses without that field keep Director changes disabled while ordinary eligible user management remains available. Accountants receive no Master capability context and still cannot open Users.


## Authentication extension — source review, not activated

Migration 002 is additive and applies only to the dedicated Audyt database after 001. AuthenticationRepository owns email verification, password login/recovery/change, Google linking, sessions and encrypted security-mail intents. AuthenticationApi accepts bounded POST JSON at /v1/auth/. Public auth routes remain disabled unless private authenticationEnabled, keys and sender are configured. Never publish private configuration, source, dependencies, jobs or backups under the website root.

When enabled, business membership endpoints accept an Audyt session rather than a raw Google token. Verified Google subject and fresh email proof bind email-first accounts to their existing immutable identity; password, memberships and roles remain unchanged. Gmail/Workspace authority may create a Google-only account after configured terms consent; other addresses need a code. Password verification uses Argon2id where supported or the documented keyed fixed-length bcrypt fallback. Password change/reset revoke sessions; Google-only recovery does not add a local password.

Security mail uses a replaceable transport and encrypted durable outbox. The initial source sender is admin@cocombee.com on NameHero; the local MTA adapter is not proof of live delivery. Worker bin/security_mail.php is CLI-only and not scheduled by this source change. Stable message IDs and locked intents reduce duplicates, but an accepted delivery followed by a crash before commit cannot guarantee exactly-once mail.

72 authentication checks passed on disposable local MariaDB, with fictional mail transport only. Additional Google signature/claim and membership API regressions passed. Authentication backup now uses the version-2 contract above; local recovery has 90 checks, including populated tables, fresh password/linked Google sign-in, unchanged roles, stale-proof invalidation, rollback and concurrent restore refusal. Version-1 archives remain supported on their matching schema. Before activation, verify actual host PHP/TLS/DB/private file denial, protected recovery keys, mail delivery/worker, reviewed published terms/privacy, operator details and host-specific recovery rehearsal. Local accounting books are a separate backup. No hosted job or mail sending was activated.

See ../output/Settings Controls Review/Authentication And Legal Plan.md for UI decisions and the later invoice/quotation sending-account selector plan. No customer or security mail was sent by this batch.
