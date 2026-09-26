<?php
declare(strict_types=1);
require __DIR__ . '/../vendor/autoload.php';

use Audyt\GoogleIdentityVerifier;
use Audyt\GoogleCertificateTransport;
use Firebase\JWT\JWT;
use Google\Auth\AccessToken;
use GuzzleHttp\Psr7\Response;

// Ephemeral test keys only. No real account, token or outbound request is used.
$key = openssl_pkey_new(['private_key_bits'=>2048, 'private_key_type'=>OPENSSL_KEYTYPE_RSA]);
if ($key === false) throw new RuntimeException('test_key_generation_failed');
$details = openssl_pkey_get_details($key);
$base64url = fn(string $bytes): string => rtrim(strtr(base64_encode($bytes), '+/', '-_'), '=');
$certs = json_encode(['keys'=>[['kty'=>'RSA', 'alg'=>'RS256', 'use'=>'sig', 'kid'=>'test-key',
    'n'=>$base64url($details['rsa']['n']), 'e'=>$base64url($details['rsa']['e'])]]], JSON_THROW_ON_ERROR);
$requests = 0;
$http = function ($request) use ($certs, &$requests) {
    if ((string)$request->getUri() !== AccessToken::FEDERATED_SIGNON_CERT_URL) {
        throw new RuntimeException('unexpected_certificate_destination');
    }
    $requests++;
    return new Response(200, ['Cache-Control'=>'public, max-age=3600'], $certs);
};
$cacheDirectory = sys_get_temp_dir().'/audyt-signature-test-'.bin2hex(random_bytes(8));
mkdir($cacheDirectory,0700);
register_shutdown_function(static function() use ($cacheDirectory) {
    foreach (glob($cacheDirectory.'/*') as $file) unlink($file);
    rmdir($cacheDirectory);
});
$verifier = new GoogleIdentityVerifier(new AccessToken(new GoogleCertificateTransport($cacheDirectory,$http)), 'audyt-test-client');
$now = time();
$claims = ['aud'=>'audyt-test-client', 'iss'=>'https://accounts.google.com', 'sub'=>'123456789',
    'email'=>'director@example.test', 'email_verified'=>true, 'iat'=>$now-10, 'exp'=>$now+600,
    'role'=>'director'];
$sign = fn(array $payload): string => JWT::encode($payload, $key, 'RS256', 'test-key');
$valid = $sign($claims);
$expected = ['googleSubject'=>'123456789', 'verifiedEmail'=>'director@example.test','authoritativeEmail'=>false];
if ($verifier->verify($valid) !== $expected) throw new RuntimeException('identity_mismatch');

$checks = 1;
$reject = function (GoogleIdentityVerifier $target, string $token, string $error='invalid_google_token') use (&$checks) {
    try { $target->verify($token); }
    catch (DomainException $e) {
        if ($e->getMessage() !== $error) throw new RuntimeException('unexpected_safe_error: '.$e->getMessage());
        $checks++;
        return;
    }
    throw new RuntimeException('unsafe_token_accepted');
};
foreach ([['aud'=>'different-client'], ['iss'=>'https://attacker.example'], ['exp'=>$now-1],
    ['iat'=>$now+3600], ['email_verified'=>false], ['sub'=>'']] as $override) {
    $reject($verifier, $sign(array_replace($claims, $override)));
}
$parts = explode('.', $valid);
$parts[1] = $base64url(json_encode(array_replace($claims, ['sub'=>'attacker']), JSON_THROW_ON_ERROR));
$reject($verifier, implode('.', $parts));
$otherKey = openssl_pkey_new(['private_key_bits'=>2048, 'private_key_type'=>OPENSSL_KEYTYPE_RSA]);
$reject($verifier, JWT::encode($claims, $otherKey, 'RS256', 'test-key'));
$reject($verifier, JWT::encode($claims, 'test-only-hmac-secret-at-least-32-bytes', 'HS256', 'test-key'));
$reject($verifier, 'not-a-token');
$reject($verifier, str_repeat('a', 16385).'.b.c');
if ($requests !== 1) throw new RuntimeException('certificate_cache_not_reused');
$checks++;
$unavailable = new GoogleIdentityVerifier(new AccessToken(function () {
    throw new RuntimeException('private HTTP failure details');
}), 'audyt-test-client');
$reject($unavailable, $valid, 'google_verification_unavailable');
echo "$checks cryptographic integration checks passed\n";
