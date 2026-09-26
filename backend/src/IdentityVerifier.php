<?php
declare(strict_types=1);
namespace Audyt;

interface IdentityVerifier
{
    /** @return array{googleSubject:string,verifiedEmail:string,authoritativeEmail?:bool} */
    public function verify(string $token): array;
}
