<?php

namespace App\Jobs;

use App\Enums\MessageChannel;
use App\Enums\MessageStatus;
use App\Models\Message;
use App\Support\Sms\SmsGatewayManager;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Hands one queued message to its gateway and records the outcome.
 *
 * On cPanel there is no long-running worker, so the deployment runs
 * `php artisan queue:work --stop-when-empty` from cron. With QUEUE_CONNECTION
 * set to "sync" the send simply happens inline, which is what the test suite
 * uses - either way the message row tells the truth about what happened.
 */
class SendMessageJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    public function __construct(private readonly int $messageId) {}

    public function handle(SmsGatewayManager $gateways): void
    {
        $message = Message::find($this->messageId);

        if ($message === null || $message->status !== MessageStatus::Queued) {
            return;
        }

        if ($message->channel === MessageChannel::InApp) {
            $message->update(['status' => MessageStatus::Sent, 'sent_at' => now()]);

            return;
        }

        if (blank($message->recipient_mobile)) {
            $message->update([
                'status' => MessageStatus::Skipped,
                'failure_reason' => 'No mobile number on record.',
            ]);

            return;
        }

        $setting = $message->school?->communicationSetting;
        $result = $gateways->gateway($message->provider)->send(
            $message->recipient_mobile,
            $message->body,
            $setting?->sender_id,
        );

        $message->update($result->accepted
            ? [
                'status' => MessageStatus::Sent,
                'sent_at' => now(),
                'provider_message_id' => $result->providerMessageId,
                'failure_reason' => null,
            ]
            : [
                'status' => MessageStatus::Failed,
                'failure_reason' => $result->failureReason,
            ]);
    }

    /**
     * A message whose job died (gateway timeout, bad credentials) must not sit
     * in "queued" for ever - admins retry it from the log.
     */
    public function failed(?Throwable $exception): void
    {
        Log::warning('Message delivery job failed', [
            'message_id' => $this->messageId,
            'exception' => $exception?->getMessage(),
        ]);

        Message::where('id', $this->messageId)
            ->where('status', MessageStatus::Queued)
            ->update([
                'status' => MessageStatus::Failed,
                'failure_reason' => 'The gateway could not be reached.',
            ]);
    }
}
