<?php

namespace App\Jobs;

use App\Models\Announcement;
use App\Models\User;
use App\Services\AnnouncementService;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Turns a published announcement into one message per recipient. This is a
 * job because a whole-school notice can be thousands of rows, and the
 * publisher should not wait for them.
 */
class PublishAnnouncementJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    public function __construct(private readonly int $announcementId, private readonly ?int $actorId = null) {}

    public function handle(AnnouncementService $announcements): void
    {
        $announcement = Announcement::find($this->announcementId);

        if ($announcement === null) {
            return;
        }

        // Someone deleted the notice before it went out; honour that.
        if ($announcement->trashed()) {
            return;
        }

        $announcements->fanOut($announcement, $this->actorId === null ? null : User::find($this->actorId));
    }

    public function failed(?Throwable $exception): void
    {
        Log::warning('Announcement fan-out failed', [
            'announcement_id' => $this->announcementId,
            'exception' => $exception?->getMessage(),
        ]);
    }
}
