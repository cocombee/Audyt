-- Apply only to a NEW, dedicated Audyt database. No existing website database.
-- MariaDB 10.11 / InnoDB. This service contains no accounting or document bytes.
CREATE TABLE audyt_businesses (
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE audyt_identities (
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    google_subject VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
    verified_google_email VARCHAR(320) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE audyt_memberships (
    business_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    identity_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    display_name VARCHAR(200) NOT NULL,
    contact_email VARCHAR(320) NOT NULL,
    status ENUM('pending','approved','rejected','revoked') NOT NULL DEFAULT 'pending',
    role ENUM('director','accountant','employee') NULL,
    requested_role ENUM('director','accountant','employee') NULL,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 0,
    submitted_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (business_id, identity_id),
    CONSTRAINT audyt_membership_business FOREIGN KEY (business_id) REFERENCES audyt_businesses(id),
    CONSTRAINT audyt_membership_identity FOREIGN KEY (identity_id) REFERENCES audyt_identities(id),
    CONSTRAINT audyt_role_state CHECK ((status='approved' AND role IS NOT NULL) OR (status<>'approved' AND role IS NULL)),
    INDEX audyt_registration_queue (business_id, status, submitted_at, identity_id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- One transaction owns state changes, this receipt and audit events.
-- The digest binds the key to a canonical command; key reuse with new content fails.
CREATE TABLE audyt_commands (
    business_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    actor_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    payload_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    result_json LONGTEXT NOT NULL CHECK (JSON_VALID(result_json)),
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (business_id, actor_id, request_id),
    FOREIGN KEY (business_id) REFERENCES audyt_businesses(id),
    FOREIGN KEY (actor_id) REFERENCES audyt_identities(id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE audyt_access_events (
    sequence_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    business_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    actor_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action ENUM('register','approve','reject','changeRole','revoke','bootstrap') NOT NULL,
    before_status VARCHAR(16) NULL,
    after_status VARCHAR(16) NOT NULL,
    before_role VARCHAR(16) NULL,
    after_role VARCHAR(16) NULL,
    revision BIGINT UNSIGNED NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    UNIQUE KEY audyt_event_retry (business_id, actor_id, request_id, target_id),
    INDEX audyt_director_notifications (business_id, action, sequence_id),
    FOREIGN KEY (business_id) REFERENCES audyt_businesses(id),
    FOREIGN KEY (actor_id) REFERENCES audyt_identities(id),
    FOREIGN KEY (target_id) REFERENCES audyt_identities(id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Initial owner is seeded explicitly during deployment, never by first signup.
-- Pending registrations cannot insert or update this table.
CREATE TABLE audyt_owner_bootstrap (
    business_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    expected_verified_email VARCHAR(320) NOT NULL,
    bound_identity_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    bound_at DATETIME(6) NULL,
    FOREIGN KEY (business_id) REFERENCES audyt_businesses(id),
    FOREIGN KEY (bound_identity_id) REFERENCES audyt_identities(id)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
