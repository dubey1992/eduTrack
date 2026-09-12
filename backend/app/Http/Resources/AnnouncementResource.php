<?php

namespace App\Http\Resources;

use App\Models\Announcement;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Announcement
 */
class AnnouncementResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'school_name' => $this->whenLoaded('school', fn () => $this->school?->name),
            'title' => $this->title,
            'body' => $this->body,
            'audience_type' => $this->audience_type->value,
            'audience_id' => $this->audience_id,
            'audience_label' => $this->audience_label,
            'channels' => $this->channels->value,
            'channels_label' => $this->channels->label(),
            'expires_at' => $this->expires_at?->toDateString(),
            'has_expired' => $this->hasExpired(),
            'published_by_name' => $this->whenLoaded('publishedBy', fn () => $this->publishedBy?->name),
            'published_at' => $this->published_at,
            'recipients_count' => $this->recipients_count,
            'sms_count' => $this->sms_count,
            'in_app_count' => $this->in_app_count,
        ];
    }
}
