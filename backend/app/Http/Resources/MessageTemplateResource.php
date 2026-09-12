<?php

namespace App\Http\Resources;

use App\Enums\MessageEvent;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Wraps one row of MessageTemplateService::listFor - an event plus the body
 * the school will actually send, whether that is its own or the default.
 */
class MessageTemplateResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        /** @var MessageEvent $event */
        $event = $this->resource['event'];

        return [
            'event' => $event->value,
            'event_label' => $event->label(),
            'category' => $event->category()->value,
            'channels' => array_map(fn ($channel) => $channel->value, $event->channels()),
            'body' => $this->resource['body'],
            'default_body' => $this->resource['default_body'],
            'is_custom' => $this->resource['is_custom'],
            'tokens' => $event->tokens(),
            'updated_at' => $this->resource['updated_at'],
            'updated_by_name' => $this->resource['updated_by_name'],
        ];
    }
}
