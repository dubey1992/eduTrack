<?php

namespace App\Models;

use App\Enums\MessageCategory;
use App\Enums\MessageChannel;
use App\Enums\MessageEvent;
use App\Enums\MessageStatus;
use Database\Factories\MessageFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'school_id',
    'event',
    'announcement_id',
    'category',
    'channel',
    'recipient_name',
    'recipient_mobile',
    'user_id',
    'student_id',
    'student_name',
    'subject',
    'body',
    'status',
    'provider',
    'provider_message_id',
    'failure_reason',
    'created_by',
    'sent_at',
    'read_at',
])]
class Message extends Model
{
    /** @use HasFactory<MessageFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'event' => MessageEvent::class,
            'category' => MessageCategory::class,
            'channel' => MessageChannel::class,
            'status' => MessageStatus::class,
            'sent_at' => 'datetime',
            'read_at' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<School, $this>
     */
    public function school(): BelongsTo
    {
        return $this->belongsTo(School::class);
    }

    /**
     * The announcement this copy came from, when it is one.
     *
     * @return BelongsTo<Announcement, $this>
     */
    public function announcement(): BelongsTo
    {
        return $this->belongsTo(Announcement::class);
    }

    /**
     * @return BelongsTo<Student, $this>
     */
    public function student(): BelongsTo
    {
        return $this->belongsTo(Student::class);
    }

    /**
     * The in-app recipient, when there is one.
     *
     * @return BelongsTo<User, $this>
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function isRetryable(): bool
    {
        return $this->status === MessageStatus::Failed;
    }
}
