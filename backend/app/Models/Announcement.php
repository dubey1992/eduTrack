<?php

namespace App\Models;

use App\Enums\AnnouncementAudience;
use App\Enums\AnnouncementChannels;
use Database\Factories\AnnouncementFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Deleting is a soft delete on purpose: it takes the notice out of the in-app
 * feed, while the messages it already sent stay in the log. A text that
 * reached a parent's phone cannot be unsent.
 */
#[Fillable([
    'school_id',
    'title',
    'body',
    'audience_type',
    'audience_id',
    'audience_label',
    'channels',
    'expires_at',
    'published_by',
    'published_at',
    'recipients_count',
    'sms_count',
    'in_app_count',
])]
class Announcement extends Model
{
    /** @use HasFactory<AnnouncementFactory> */
    use HasFactory;

    use SoftDeletes;

    protected function casts(): array
    {
        return [
            'audience_type' => AnnouncementAudience::class,
            'channels' => AnnouncementChannels::class,
            'expires_at' => 'date',
            'published_at' => 'datetime',
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
     * @return BelongsTo<User, $this>
     */
    public function publishedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'published_by');
    }

    /**
     * @return HasMany<Message, $this>
     */
    public function messages(): HasMany
    {
        return $this->hasMany(Message::class);
    }

    public function hasExpired(): bool
    {
        return $this->expires_at !== null && $this->expires_at->isPast();
    }
}
