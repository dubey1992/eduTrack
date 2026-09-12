<?php

namespace App\Http\Resources;

use App\Http\Resources\Concerns\RendersSchoolTime;
use App\Models\Message;
use App\Support\Sms\SmsGatewayManager;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Message
 */
class MessageResource extends JsonResource
{
    use RendersSchoolTime;

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'event' => $this->event->value,
            'event_label' => $this->event->label(),
            'category' => $this->category->value,
            'category_label' => $this->category->label(),
            'channel' => $this->channel->value,
            'channel_label' => $this->channel->label(),
            'recipient_name' => $this->recipient_name,
            'recipient_mobile' => $this->recipient_mobile,
            'student_id' => $this->student_id,
            'student_name' => $this->student_name,
            'announcement_id' => $this->announcement_id,
            'subject' => $this->subject,
            'body' => $this->body,
            'status' => $this->status->value,
            'status_label' => $this->status->label(),
            'provider' => $this->provider,
            'provider_label' => $this->provider === null ? null : app(SmsGatewayManager::class)->label($this->provider),
            'failure_reason' => $this->failure_reason,
            'sent_at' => $this->sent_at,
            'read_at' => $this->read_at,
            'created_at' => $this->created_at,
            // Rendered server-side in the school's own timezone, so the log
            // agrees with the time written inside the message itself - and
            // with the clock on the wall wherever the school is.
            'created_at_label' => $this->timeLabel($this->created_at),
            'created_on_label' => $this->dateLabel($this->created_at),
            'sent_at_label' => $this->timeLabel($this->sent_at),
            'timezone' => $this->clock()->timezone(),
        ];
    }
}
