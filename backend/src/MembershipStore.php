<?php
declare(strict_types=1);
namespace Audyt;

interface MembershipStore
{
    public function register(string $businessId, array $verifiedIdentity, string $requestId, array $profile): array;
    public function selfMembership(string $businessId, string $verifiedSubject): ?array;
    public function notifications(string $businessId, string $actorId, int $after = 0, int $limit = 50): array;
    public function directory(string $businessId, string $actorId, int $offset = 0, int $limit = 10, string $search = ''): array;
    public function command(string $businessId, string $actorId, string $requestId, array $expectedRevisions, string $action, ?string $role = null): array;
}
