<?php

namespace App\Services;

use App\Enums\AttendanceAlertMode;
use App\Enums\MessageCategory;
use App\Enums\MessageChannel;
use App\Enums\MessageEvent;
use App\Enums\MessageStatus;
use App\Jobs\SendMessageJob;
use App\Models\Announcement;
use App\Models\CommunicationSetting;
use App\Models\Message;
use App\Models\Student;
use App\Models\User;
use App\Support\TemplateRenderer;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * The only way the rest of the product sends anything. Callers describe what
 * happened (a MessageEvent plus its tokens) and never touch a gateway, a
 * template or a channel themselves.
 *
 * Nothing here throws: a switched-off alert or a missing mobile number is
 * recorded as a skipped message so it still shows up in the log, and the
 * actual send is queued after the caller's transaction commits so submitting
 * attendance is never held up by an SMS.
 */
class NotificationService
{
    public function __construct(
        private readonly CommunicationSettingService $settings,
        private readonly MessageTemplateService $templates,
        private readonly TemplateRenderer $renderer,
    ) {}

    /**
     * Alerts a student's guardian. Guardians have no login, so this is SMS only.
     *
     * @param  array<string, string|null>  $tokens
     * @param  array<int, MessageChannel>|null  $channels  Overrides the event's own channels (an announcement picks its own).
     * @return array<int, Message>
     */
    public function notifyGuardian(
        MessageEvent $event,
        Student $student,
        array $tokens,
        ?User $actor = null,
        ?array $channels = null,
        ?Announcement $announcement = null,
    ): array {
        $student->loadMissing('school');

        $tokens = array_merge([
            'student_name' => $student->name,
            'guardian_name' => $student->guardian_name,
            'school_name' => $student->school?->name,
            'date' => now()->format('d M Y'),
            'time' => now()->format('g:i A'),
        ], $tokens);

        return $this->record(
            event: $event,
            schoolId: $student->school_id,
            recipientName: $student->guardian_name,
            mobile: $student->guardian_mobile,
            tokens: $tokens,
            actor: $actor,
            student: $student,
            channels: $channels,
            announcement: $announcement,
        );
    }

    /**
     * Alerts a member of staff, in their inbox and by SMS.
     *
     * @param  array<string, string|null>  $tokens
     * @param  array<int, MessageChannel>|null  $channels  Overrides the event's own channels.
     * @return array<int, Message>
     */
    public function notifyUser(
        MessageEvent $event,
        User $user,
        array $tokens,
        ?User $actor = null,
        ?array $channels = null,
        ?Announcement $announcement = null,
    ): array {
        $user->loadMissing('school');

        $tokens = array_merge([
            'staff_name' => $user->name,
            'school_name' => $user->school?->name,
            'date' => now()->format('d M Y'),
        ], $tokens);

        return $this->record(
            event: $event,
            schoolId: $user->school_id,
            recipientName: $user->name,
            mobile: $user->mobile,
            tokens: $tokens,
            actor: $actor,
            user: $user,
            channels: $channels,
            announcement: $announcement,
        );
    }

    /**
     * @param  array<string, string|null>  $tokens
     * @param  array<int, MessageChannel>|null  $channels
     * @return array<int, Message>
     */
    private function record(
        MessageEvent $event,
        ?int $schoolId,
        string $recipientName,
        ?string $mobile,
        array $tokens,
        ?User $actor,
        ?Student $student = null,
        ?User $user = null,
        ?array $channels = null,
        ?Announcement $announcement = null,
    ): array {
        if ($schoolId === null) {
            return [];
        }

        $setting = $this->settings->for($schoolId);

        // A school that switched this alert off is not "skipping" anything -
        // it never wanted the message, and one row per student per day would
        // bury the log. Only a message the school did want, but that could
        // not be delivered, is worth recording as skipped.
        if ($this->isSwitchedOff($event, $setting)) {
            return [];
        }

        $body = $this->renderer->render($this->templates->bodyFor($schoolId, $event), $tokens);
        $messages = [];

        foreach ($channels ?? $event->channels() as $channel) {
            [$status, $reason] = $this->outcomeFor($channel, $setting->sms_enabled, $mobile);

            if ($status === null) {
                continue;
            }

            // Callers write this from inside their own transaction (marking a
            // register, ending a trip). A messaging problem must never roll
            // their work back, so it is logged and swallowed here.
            try {
                $messages[] = $this->write([
                    'school_id' => $schoolId,
                    'event' => $event,
                    'announcement_id' => $announcement?->id,
                    'category' => $event->category(),
                    'channel' => $channel,
                    'recipient_name' => $recipientName,
                    'recipient_mobile' => $channel === MessageChannel::Sms ? $mobile : null,
                    'user_id' => $user?->id,
                    'student_id' => $student?->id,
                    'student_name' => $student?->name,
                    'subject' => $announcement?->title,
                    'body' => $body,
                    'status' => $status,
                    'provider' => $channel === MessageChannel::Sms ? $setting->provider : null,
                    'failure_reason' => $reason,
                    'created_by' => $actor?->id,
                    'sent_at' => $status === MessageStatus::Sent ? now() : null,
                ]);
            } catch (Throwable $e) {
                Log::error('Could not record an outgoing message', [
                    'event' => $event->value,
                    'channel' => $channel->value,
                    'school_id' => $schoolId,
                    'exception' => $e->getMessage(),
                ]);
            }
        }

        foreach ($messages as $message) {
            if ($message->status === MessageStatus::Queued) {
                DB::afterCommit(fn () => SendMessageJob::dispatch($message->id));
            }
        }

        return $messages;
    }

    /**
     * @param  array<string, mixed>  $attributes
     */
    private function write(array $attributes): Message
    {
        return Message::create($attributes);
    }

    /**
     * Has the school turned this kind of alert off?
     */
    private function isSwitchedOff(MessageEvent $event, CommunicationSetting $setting): bool
    {
        return match ($event->category()) {
            MessageCategory::Attendance => match ($setting->attendance_alerts) {
                AttendanceAlertMode::Off => true,
                AttendanceAlertMode::AbsentOnly => $event === MessageEvent::AttendancePresent,
                AttendanceAlertMode::PresentAndAbsent => false,
            },
            MessageCategory::Transport => ! $setting->transport_alerts_enabled,
            MessageCategory::Leave => ! $setting->leave_alerts_enabled,
            default => false,
        };
    }

    /**
     * What becomes of this channel's copy. A null status means the message is
     * not recorded at all.
     *
     * @return array{0: MessageStatus|null, 1: string|null}
     */
    private function outcomeFor(MessageChannel $channel, bool $smsEnabled, ?string $mobile): array
    {
        if ($channel === MessageChannel::InApp) {
            return [MessageStatus::Queued, null];
        }

        if (! $smsEnabled) {
            return [null, null];
        }

        // The school wanted to text this person but has no number for them -
        // that is a record to fix, so it belongs in the log.
        if (blank($mobile)) {
            return [MessageStatus::Skipped, 'No mobile number on record.'];
        }

        return [MessageStatus::Queued, null];
    }
}
