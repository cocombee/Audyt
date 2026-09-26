<?php
// Copy to config.local.php OUTSIDE public/, mode 0600. Never commit credentials.
return [
    'dsn'=>'mysql:host=localhost;dbname=cocombee_audyt;charset=utf8mb4',
    'databaseUser'=>'cocombee_audyt',
    'databasePassword'=>'', // Enter privately on the hosting account.
    'googleAudience'=>'622467919105-iu4oes965euqpnko5nidf9v1mgqkm7k9.apps.googleusercontent.com',
    'certificateDirectory'=>__DIR__.'/var/certificates', // Precreate mode 0700.
    'rateDirectory'=>__DIR__.'/var/rate', // Precreate mode 0700.
    'rateKey'=>'', // Generate at least 32 random bytes; do not reuse a password.
    'authenticationEnabled'=>false, // Activate only after private provisioning and host checks.
    'authenticationKey'=>'', // Base64 of 32 random bytes; password pepper/code key.
    'mailEncryptionKey'=>'', // Base64 of a DIFFERENT 32 random bytes; outbox encryption.
    'passwordDummyHash'=>'', // Same-cost password hash generated with AuthenticationSecrets.
    'termsVersion'=>'', // Reviewed published agreement version; blank blocks new registration.
    'securityMailSender'=>'admin@cocombee.com', // Existing verified NameHero mailbox, private configuration.
    'backupKey'=>'', // Base64 of 32 random bytes. Keep separately from backup archives.
];
