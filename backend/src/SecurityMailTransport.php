<?php
declare(strict_types=1);
namespace Audyt;

interface SecurityMailTransport
{
    /** Mail-server acceptance only; never a claim of recipient inbox delivery. */
    public function send(string $id,array $payload): void;
}
