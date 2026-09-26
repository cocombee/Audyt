-- Additive authentication schema for the dedicated Audyt database only.
-- Existing membership identities and approvals are retained. No DROP/DELETE.
CREATE TABLE audyt_auth_guard (id TINYINT UNSIGNED PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO audyt_auth_guard (id) VALUES (1);
CREATE TABLE audyt_auth_email_locks (
  email_key CHAR(64) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY
) ENGINE=InnoDB;
CREATE TABLE audyt_auth_accounts (
  identity_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
  email_key CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
  email VARCHAR(320) NOT NULL,
  display_name VARCHAR(200) NOT NULL,
  phone VARCHAR(40) NOT NULL DEFAULT '',
  password_hash VARCHAR(255) NULL,
  terms_version VARCHAR(80) NOT NULL,
  terms_accepted_at DATETIME(6) NOT NULL,
  created_at DATETIME(6) NOT NULL,
  CONSTRAINT audyt_auth_identity FOREIGN KEY (identity_id) REFERENCES audyt_identities(id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE TABLE audyt_auth_challenges (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
  email_key CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  email VARCHAR(320) NOT NULL,
  purpose ENUM('register','google-register','reset','link','unavailable') NOT NULL,
  payload_json TEXT NOT NULL CHECK (JSON_VALID(payload_json)),
  code_digest CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
  resends TINYINT UNSIGNED NOT NULL DEFAULT 0,
  last_sent_at DATETIME(6) NOT NULL,
  created_at DATETIME(6) NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  consumed_at DATETIME(6) NULL,
  INDEX audyt_auth_challenge_email (email_key,purpose,consumed_at)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE TABLE audyt_auth_sessions (
  token_digest CHAR(64) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
  identity_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at DATETIME(6) NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  revoked_at DATETIME(6) NULL,
  CONSTRAINT audyt_auth_session_identity FOREIGN KEY (identity_id) REFERENCES audyt_auth_accounts(identity_id),
  INDEX audyt_auth_session_account (identity_id,revoked_at)
) ENGINE=InnoDB;
CREATE TABLE audyt_auth_limits (
  subject_key CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  action VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  bucket BIGINT UNSIGNED NOT NULL,
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY(subject_key,action,bucket)
) ENGINE=InnoDB;
CREATE TABLE audyt_auth_events (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
  identity_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
  event VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at DATETIME(6) NOT NULL,
  CONSTRAINT audyt_auth_event_identity FOREIGN KEY (identity_id) REFERENCES audyt_identities(id)
) ENGINE=InnoDB;
CREATE TABLE audyt_mail_outbox (
  id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
  challenge_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
  encrypted_payload MEDIUMTEXT NULL,
  state ENUM('queued','accepted','cancelled') NOT NULL DEFAULT 'queued',
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME(6) NOT NULL,
  next_attempt_at DATETIME(6) NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  accepted_at DATETIME(6) NULL,
  INDEX audyt_mail_ready (state,next_attempt_at)
) ENGINE=InnoDB;
