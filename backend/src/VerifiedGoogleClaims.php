<?php
declare(strict_types=1);
namespace Audyt;

/** Additional claim checks. Call ONLY after successful cryptographic verification. */
final class VerifiedGoogleClaims
{
    public static function identity(array $claims, string $audience, int $now): array
    {
        if (($claims['aud'] ?? null) !== $audience
            || !in_array($claims['iss'] ?? null, ['accounts.google.com','https://accounts.google.com'], true)
            || !is_int($claims['exp'] ?? null) || $claims['exp'] <= $now
            || !is_int($claims['iat'] ?? null) || $claims['iat'] > $now + 60
            || ($claims['email_verified'] ?? null) !== true
            || !is_string($claims['sub'] ?? null)
            || preg_match('/^[\x21-\x7e]{1,255}$/D', $claims['sub']) !== 1
            || !is_string($claims['email'] ?? null) || strlen($claims['email']) > 320
            || !str_contains($claims['email'], '@')
            || preg_match('/[\x00-\x20\x7f]/', $claims['email'])) {
            throw new \DomainException('invalid_google_token');
        }
        return ['googleSubject'=>$claims['sub'], 'verifiedEmail'=>$claims['email'],
            'authoritativeEmail'=>str_ends_with(strtolower($claims['email']),'@gmail.com') || (is_string($claims['hd'] ?? null) && $claims['hd']!=='')];
    }
}
