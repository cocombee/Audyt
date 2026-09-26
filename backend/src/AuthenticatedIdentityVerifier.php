<?php
declare(strict_types=1);
namespace Audyt;

/** Require the linked, revocable Audyt session after authentication is enabled.
 * Neither source provides roles: MembershipRepository rechecks company access.
 */
final class AuthenticatedIdentityVerifier implements IdentityVerifier
{
    public function __construct(private IdentityVerifier $google,private AuthenticationRepository $authentication) {}
    public function verify(string $token): array {
        if (!str_starts_with($token,'audyt_')) throw new \DomainException('authentication_required');
        return $this->authentication->verifiedIdentity($token);
    }
}
