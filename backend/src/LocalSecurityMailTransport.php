<?php
declare(strict_types=1);
namespace Audyt;

/** cPanel's local MTA, with a privately configured existing NameHero mailbox.
 * Replace this adapter for authenticated SMTP/provider delivery later. No mail
 * is sent by constructing it. Never pass caller-controlled shell parameters.
 */
final class LocalSecurityMailTransport implements SecurityMailTransport
{
    private string $domain;
    public function __construct(private string $sender) {
        $sender=AuthenticationRepository::email($sender);
        if ($sender!==$this->sender) throw new \InvalidArgumentException('invalid_sender');
        $this->domain=explode('@',$sender)[1];
    }
    public function send(string $id,array $payload): void {
        $recipient=AuthenticationRepository::email($payload['to'] ?? '');
        if (!preg_match('/^[a-f0-9-]{36}$/D',$id) || !is_string($payload['subject'] ?? null) || !is_string($payload['text'] ?? null)
            || strlen($payload['subject'])>200 || strlen($payload['text'])>8000 || preg_match('/[\r\n\x00]/',$payload['subject'])) throw new \RuntimeException('invalid_mail_payload');
        $headers=['From'=>'Audyt <'.$this->sender.'>', 'MIME-Version'=>'1.0', 'Content-Type'=>'text/plain; charset=UTF-8',
            'Message-ID'=>'<'.$id.'@'.$this->domain.'>', 'Auto-Submitted'=>'auto-generated'];
        if (!mail($recipient,$payload['subject'],$payload['text'],$headers)) throw new \RuntimeException('mail_not_accepted');
    }
}
