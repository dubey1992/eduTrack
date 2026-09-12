<?php

namespace App\Services;

use App\Enums\MessageChannel;
use App\Enums\MessageStatus;
use App\Enums\UserRole;
use App\Jobs\SendMessageJob;
use App\Models\Message;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Carbon;

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
            ->with(['student', 'user'])
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
        $today = Carbon::today();
        $todayQuery = $this->scoped($actor, $filters)->whereDate('created_at', $today);

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
                        ->orWhereDate('expires_at', '>=', now()->toDateString()))));
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
    private function scoped(User $actor, array $filters): Builder
    {
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
            ->when($filters['date_from'] ?? null, fn (Builder $query, $date) => $query->whereDate('created_at', '>=', $date))
            ->when($filters['date_to'] ?? null, fn (Builder $query, $date) => $query->whereDate('created_at', '<=', $date))
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
