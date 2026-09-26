<?php
declare(strict_types=1);
namespace Audyt;

use Google\Auth\AccessToken;

/** Verify signatures through Google's library, then enforce Audyt's identity contract. */
final class GoogleIdentityVerifier implements IdentityVerifier
{
    public static function forHosting(string $audience, string $privateCacheDirectory): self
    {
        return new self(new AccessToken(new GoogleCertificateTransport($privateCacheDirectory)), $audience);
    }

    public function __construct(private AccessToken $verifier, private string $audience)
    {
        if ($audience === '') throw new \InvalidArgumentException('missing_google_audience');
    }

    /** Returns identity information only; a Google token never grants an Audyt role. */
    public function verify(string $token): array
    {
        if (strlen($token) > 16384 || substr_count($token, '.') !== 2) {
            throw new \DomainException('invalid_google_token');
        }
        try {
            // Never accept certificate URLs or issuer/audience settings from the request.
            $claims = $this->verifier->verify($token, ['audience'=>$this->audience]);
        } catch (\RuntimeException $error) {
            // Do not expose exceptions that could include token or HTTP content.
            throw new \DomainException('google_verification_unavailable');
        } catch (\Throwable $error) {
            throw new \DomainException('invalid_google_token');
        }
        if (!is_array($claims)) throw new \DomainException('invalid_google_token');
        return VerifiedGoogleClaims::identity($claims, $this->audience, time());
    }
}
