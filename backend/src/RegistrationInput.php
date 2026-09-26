<?php
declare(strict_types=1);
namespace Audyt;

final class RegistrationInput
{
    /** Validate profile data separately from the provider-verified identity. */
    public static function profile(array $input): array
    {
        if (array_diff(array_keys($input), ['name', 'email', 'requestedRole'])) {
            throw new \DomainException('unknown_profile_field');
        }
        foreach (['name'=>200, 'email'=>320] as $field=>$length) {
            if (!is_string($input[$field] ?? null) || preg_match('//u', $input[$field]) !== 1
                || mb_strlen($input[$field]) > $length
                || preg_match('/[\x00-\x1f\x7f]/u', $input[$field])) {
                throw new \DomainException('invalid_profile');
            }
            $input[$field] = trim($input[$field]);
            if ($input[$field] === '') throw new \DomainException('invalid_profile');
        }
        if (filter_var($input['email'], FILTER_VALIDATE_EMAIL) === false
            || !in_array($input['requestedRole'] ?? null, ['director','accountant','employee'], true)) {
            throw new \DomainException('invalid_profile');
        }
        return ['name'=>$input['name'], 'email'=>$input['email'], 'requestedRole'=>$input['requestedRole']];
    }
}
