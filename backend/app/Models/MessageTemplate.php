<?php

namespace App\Models;

use App\Enums\MessageEvent;
use Database\Factories\MessageTemplateFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['school_id', 'event', 'body', 'is_active', 'updated_by'])]
class MessageTemplate extends Model
{
    /** @use HasFactory<MessageTemplateFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'event' => MessageEvent::class,
            'is_active' => 'boolean',
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
    public function updatedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'updated_by');
    }
}
