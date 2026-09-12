<?php

namespace App\Support\Sms;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * The prototype's "Demo Gateway". Writes the message to the application log
 * and reports it accepted, so the whole pipeline can be exercised without a
 * provider account. Mobile numbers are masked - the log file is not a place
 * for contact details.
 */
class LogSmsGateway implements SmsGateway
{
    public function name(): string
    {
        return 'log';
    }

    public function send(string $mobile, string $body, ?string $senderId = null): SmsResult
    {
        Log::info('SMS dispatched via the demo gateway', [
            'to' => $this->mask($mobile),
            'sender_id' => $senderId,
            'length' => mb_strlen($body),
        ]);

        return SmsResult::accepted('demo-'.Str::uuid()->toString());
    }

    private function mask(string $mobile): string
    {
        return mb_strlen($mobile) <= 4 ? '****' : Str::mask($mobile, '*', 0, mb_strlen($mobile) - 4);
    }
}
