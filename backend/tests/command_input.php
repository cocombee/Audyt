<?php
declare(strict_types=1);
require __DIR__ . '/../src/CommandInput.php';
use Audyt\CommandInput;

$valid = '12345678-1234-1234-1234-123456789abc';
$cases = [
    [str_repeat('-', 36), ['one'=>0], 'invalid_request_id'],
    [str_repeat('a', 36), ['one'=>0], 'invalid_request_id'],
    [$valid . "\n", ['one'=>0], 'invalid_request_id'],
    [$valid, [], 'invalid_batch_size'],
    [$valid, array_fill(0, 101, 0), 'invalid_batch_size'],
    [$valid, ['one'=>'0'], 'invalid_revision'],
    [$valid, ['one'=>0.0], 'invalid_revision'],
    [$valid, ['one'=>true], 'invalid_revision'],
    [$valid, ['one'=>-1], 'invalid_revision'],
    [$valid, ['one'=>PHP_INT_MAX], 'invalid_revision'],
];
foreach ($cases as [$id, $revisions, $expected]) {
    try {
        CommandInput::validate($id, $revisions);
    } catch (DomainException $error) {
        if ($error->getMessage() === $expected) continue;
        throw $error;
    }
    throw new RuntimeException('Expected ' . $expected);
}
CommandInput::validate($valid, ['one'=>0]);
CommandInput::validate($valid, array_fill(0, 100, 42));
echo "12 command input checks passed\n";
