<?php
declare(strict_types=1);
namespace Audyt;

/** Reject malformed retry keys and unbounded batches before opening a transaction. */
final class CommandInput
{
    public static function validate(string $requestId, array $expectedRevisions): void
    {
        if (!preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/D', $requestId)) {
            throw new \DomainException('invalid_request_id');
        }
        if (count($expectedRevisions) < 1 || count($expectedRevisions) > 100) {
            throw new \DomainException('invalid_batch_size');
        }
        foreach ($expectedRevisions as $revision) {
            if (!is_int($revision) || $revision < 0 || $revision === PHP_INT_MAX) {
                throw new \DomainException('invalid_revision');
            }
        }
    }
}
