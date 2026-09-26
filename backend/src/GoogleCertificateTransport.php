<?php
declare(strict_types=1);
namespace Audyt;

use Google\Auth\AccessToken;
use GuzzleHttp\Client;
use GuzzleHttp\Psr7\Response;
use Psr\Http\Message\RequestInterface;
use Psr\Http\Message\ResponseInterface;

/** Dedicated Google public-key transport; contains no user credentials or tokens. */
final class GoogleCertificateTransport
{
    private \Closure $fetch;

    /** Directory must already exist outside the public web root, mode 0700. */
    public function __construct(private string $directory, ?\Closure $fetch = null)
    {
        if (!is_dir($directory) || is_link($directory) || (fileperms($directory) & 0077) !== 0) {
            throw new \InvalidArgumentException('private_certificate_cache_required');
        }
        $this->fetch = $fetch ?? static fn(RequestInterface $request): ResponseInterface =>
            (new Client())->send($request, [
                'verify'=>true, 'allow_redirects'=>false, 'http_errors'=>false,
                'connect_timeout'=>3, 'timeout'=>8, 'read_timeout'=>3, 'stream'=>true,
                'headers'=>['Accept'=>'application/json'],
            ]);
    }

    public function __invoke(RequestInterface $request, array $ignoredOptions = []): ResponseInterface
    {
        if ($request->getMethod() !== 'GET'
            || (string)$request->getUri() !== AccessToken::FEDERATED_SIGNON_CERT_URL) {
            throw new \RuntimeException('certificate_destination_denied');
        }
        $path = $this->directory.'/google-certificates.json';
        $lockPath = $this->directory.'/google-certificates.lock';
        if (is_link($path) || is_link($lockPath)) throw new \RuntimeException('unsafe_certificate_cache');
        $lock = fopen($lockPath, 'c');
        if ($lock === false) throw new \RuntimeException('certificate_cache_unavailable');
        chmod($lockPath, 0600);
        try {
            if (!flock($lock, LOCK_EX | LOCK_NB)) throw new \RuntimeException('certificate_refresh_busy');
            $now = time();
            if (is_file($path) && filesize($path) <= 140000) {
                $cached = json_decode((string)file_get_contents($path), true);
                if (is_array($cached) && is_int($cached['expires'] ?? null)
                    && $cached['expires'] > $now && $cached['expires'] <= $now + 3600
                    && is_string($cached['body'] ?? null) && self::valid($cached['body'])) {
                    return new Response(200, ['Cache-Control'=>'max-age='.($cached['expires']-$now)], $cached['body']);
                }
            }
            $response = ($this->fetch)($request);
            if ($response->getStatusCode() !== 200) throw new \RuntimeException('certificate_fetch_failed');
            $stream = $response->getBody();
            $body = '';
            $deadline = microtime(true) + 8;
            try {
                while (!$stream->eof()) {
                    if (microtime(true) > $deadline) throw new \RuntimeException('certificate_fetch_timeout');
                    $chunk = $stream->read(8192);
                    if ($chunk === '' && !$stream->eof()) throw new \RuntimeException('certificate_fetch_stalled');
                    $body .= $chunk;
                    if (strlen($body) > 65536) throw new \RuntimeException('certificate_response_too_large');
                }
            } finally { $stream->close(); }
            if (!self::valid($body)) throw new \RuntimeException('invalid_certificate_response');
            $ttl = 0;
            $control = $response->getHeaderLine('Cache-Control');
            if (!preg_match('/(?:no-store|no-cache)/i', $control)
                && preg_match('/(?:^|,)\s*max-age=(\d+)/i', $control, $match)) {
                $ttl = max(0, min(3600, (int)$match[1] - max(0, (int)$response->getHeaderLine('Age'))));
            }
            // Atomic replacement prevents workers reading a partial JSON cache.
            if ($ttl > 0) {
                $temporary = tempnam($this->directory, 'cert-');
                if ($temporary === false) throw new \RuntimeException('certificate_cache_unavailable');
                try {
                    chmod($temporary, 0600);
                    $json = json_encode(['expires'=>$now+$ttl,'body'=>$body], JSON_THROW_ON_ERROR);
                    if (file_put_contents($temporary,$json) !== strlen($json) || !rename($temporary,$path)) {
                        throw new \RuntimeException('certificate_cache_unavailable');
                    }
                } finally { if (is_file($temporary)) unlink($temporary); }
            }
            return new Response(200, ['Cache-Control'=>'max-age='.$ttl], $body);
        } finally {
            flock($lock, LOCK_UN);
            fclose($lock);
        }
    }

    private static function valid(string $body): bool
    {
        if (strlen($body) > 65536) return false;
        $data = json_decode($body, true, 16);
        if (!is_array($data) || !is_array($data['keys'] ?? null)
            || count($data['keys']) < 1 || count($data['keys']) > 10) return false;
        foreach ($data['keys'] as $key) {
            if (!is_array($key) || ($key['kty'] ?? null) !== 'RSA' || ($key['alg'] ?? null) !== 'RS256') return false;
            foreach (['kid','n','e'] as $field) {
                if (!is_string($key[$field] ?? null) || $key[$field] === '' || strlen($key[$field]) > 2048) return false;
            }
        }
        return true;
    }
}
