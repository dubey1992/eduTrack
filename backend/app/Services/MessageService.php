<?php

namespace App\Services;

use App\Enums\MessageChannel;
use App\Enums\MessageStatus;
use App\Enums\UserRole;
use App\Jobs\SendMessageJob;
use App\Models\CommunicationSetting;
use App\Models\Message;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolClock;
use App\Support\Sms\SmsGatewayManager;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Pagination\LengthAwarePaginator;

/**
 * Reading and re-driving the message log - the prototype's Communication
 * Center. Sending lives in NotificationService; nothing here creates a
 * message from scratch.
 */
class MessageService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return $this->scoped($actor, $filters)
            // 'school' is loaded for the timezone the resource renders in.
            ->with(['student', 'user', 'school'])
            ->latest('created_at')
            ->latest('id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * The four KPI tiles: today's volume, how much of it landed, what failed,
     * and how much never left the building.
     *
     * @param  array<string, mixed>  $filters
     * @return array<string, mixed>
     */
    public function summary(User $actor, array $filters): array
    {
        [$dayStart, $dayEnd] = SchoolClock::forScope($actor, $filters['school_id'] ?? null)->todayRange();
        $gateways = app(SmsGatewayManager::class);
        $provider = CommunicationSetting::query()
            ->where('school_id', $this->schoolIdFor($actor, $filters))
            ->value('provider');
        $todayQuery = $this->scoped($actor, $filters)
            ->where('created_at', '>=', $dayStart)
            ->where('created_at', '<', $dayEnd);

        $sentToday = (clone $todayQuery)->where('status', MessageStatus::Sent)->count();
        $smsSentToday = (clone $todayQuery)
            ->where('status', MessageStatus::Sent)
            ->where('channel', MessageChannel::Sms)
            ->count();
        $failedToday = (clone $todayQuery)->where('status', MessageStatus::Failed)->count();
        $queuedToday = (clone $todayQuery)->where('status', MessageStatus::Queued)->count();
        $skippedToday = (clone $todayQuery)->where('status', MessageStatus::Skipped)->count();

        $attempted = $sentToday + $failedToday;

        return [
            'sent_today' => $sentToday,
            // The prototype's tile says "SMS Sent Today", so it must not
            // count the in-app copies sitting alongside them.
            'sms_sent_today' => $smsSentToday,
            'queued_today' => $queuedToday,
            'failed_today' => $failedToday,
            'skipped_today' => $skippedToday,
            'delivery_rate' => $attempted === 0 ? null : round($sentToday / $attempted * 100, 1),
            'total' => $this->scoped($actor, $filters)->count(),
            // What is actually carrying these messages. Until a real provider
            // is configured the answer is a gateway that delivers nothing,
            // and the screen has to say so next to the word "Sent".
            'provider_label' => $gateways->label($provider),
            'provider_delivers' => $gateways->delivers($provider),
        ];
    }

    /**
     * Puts a failed message back on the queue. The body is not rebuilt - the
     * log must keep showing what was actually sent.
     */
    public function retry(Message $message): Message
    {
        $message->update([
            'status' => MessageStatus::Queued,
            'failure_reason' => null,
        ]);

        SendMessageJob::dispatch($message->id);

        return $message->refresh();
    }

    /**
     * @param  array<string, mixed>  $filters
     */
    public function inbox(User $actor, array $filters): LengthAwarePaginator
    {
        return $this->inboxQuery($actor)
            ->with('school')
            ->when($filters['unread'] ?? null, fn (Builder $query) => $query->whereNull('read_at'))
            ->latest('created_at')
            ->latest('id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    public function unreadCount(User $actor): int
    {
        return $this->inboxQuery($actor)->whereNull('read_at')->count();
    }

    /**
     * The inbox is the in-app channel only. A leave decision also goes out by
     * SMS, and that copy belongs in the log, not in the reader's inbox.
     *
     * @return Builder<Message>
     */
    private function inboxQuery(User $actor): Builder
    {
        return Message::query()
            ->where('user_id', $actor->id)
            ->where('channel', MessageChannel::InApp)
            ->whereIn('status', [MessageStatus::Sent, MessageStatus::Queued])
            // An announcement that was deleted or has expired drops out of the
            // feed. Its messages stay in the log either way.
            ->where(fn (Builder $query) => $query
                ->whereNull('announcement_id')
                ->orWhereHas('announcement', fn (Builder $announcement) => $announcement
                    ->where(fn (Builder $live) => $live
                        ->whereNull('expires_at')
                        ->orWhereDate('expires_at', '>=', SchoolClock::forUser($actor)->date()))));
    }

    public function markRead(Message $message): Message
    {
        if ($message->read_at === null) {
            $message->update(['read_at' => now()]);
        }

        return $message->refresh();
    }

    public function markAllRead(User $actor): int
    {
        return $this->inboxQuery($actor)->whereNull('read_at')->update(['read_at' => now()]);
    }

    /**
     * @param  array<string, mixed>  $filters
     * @return Builder<Message>
     */
    /**
     * Which school's settings decide the gateway. A Super Admin looking
     * across every school has none, so the platform default answers.
     *
     * @param  array<string, mixed>  $filters
     */
    private function schoolIdFor(User $actor, array $filters): ?int
    {
        if ($actor->role !== UserRole::SuperAdmin) {
            return $actor->school_id;
        }

        $schoolId = $filters['school_id'] ?? null;

        return $schoolId === null ? null : (int) $schoolId;
    }

    private function scoped(User $actor, array $filters): Builder
    {
        $clock = SchoolClock::forScope($actor, $filters['school_id'] ?? null);

        return Message::query()
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn (Builder $query) => $query->where('school_id', $actor->school_id),
                fn (Builder $query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn (Builder $query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
            ->when($filters['category'] ?? null, fn (Builder $query, $category) => $query->where('category', $category))
            ->when($filters['channel'] ?? null, fn (Builder $query, $channel) => $query->where('channel', $channel))
            ->when($filters['status'] ?? null, fn (Builder $query, $status) => $query->where('status', $status))
            // The dates come off a date picker, so they mean days at the
            // school; created_at is a UTC instant. Compare windows, not dates.
            ->when(
                $filters['date_from'] ?? null,
                fn (Builder $query, $date) => $query->where('created_at', '>=', $clock->startOfDayUtc($date))
            )
            ->when(
                $filters['date_to'] ?? null,
                fn (Builder $query, $date) => $query->where('created_at', '<', $clock->endOfDayUtc($date))
            )
            ->when($filters['q'] ?? null, function (Builder $query, string $term) {
                $like = '%'.$term.'%';
                $query->where(fn (Builder $inner) => $inner
                    ->where('recipient_name', 'like', $like)
                    ->orWhere('student_name', 'like', $like)
                    ->orWhere('recipient_mobile', 'like', $like)
                    ->orWhere('body', 'like', $like));
            });
    }
}
