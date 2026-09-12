<?php

namespace App\Services;

use App\Enums\MessageEvent;
use App\Models\MessageTemplate;
use App\Models\School;
use App\Models\User;
use Illuminate\Support\Collection;

/**
 * The wording of every automatic message. A school only gets a row when it
 * overrides an event, so the defaults in MessageEvent stay the single source
 * of truth for everyone else.
 */
class MessageTemplateService
{
    /**
     * Every event with the body the school will actually send.
     *
     * @return Collection<int, array<string, mixed>>
     */
    public function listFor(int $schoolId): Collection
    {
        $overrides = MessageTemplate::query()
            ->where('school_id', $schoolId)
            ->get()
            ->keyBy(fn (MessageTemplate $template) => $template->event->value);

        return collect(MessageEvent::cases())->map(function (MessageEvent $event) use ($overrides, $schoolId) {
            $override = $overrides->get($event->value);

            return [
                'school_id' => $schoolId,
                'event' => $event,
                'body' => $this->bodyFor($schoolId, $event, $override),
                'default_body' => $event->defaultBody(),
                'is_custom' => $override !== null && $override->is_active,
                'updated_at' => $override?->updated_at,
                'updated_by_name' => $override?->updatedBy?->name,
            ];
        });
    }

    public function bodyFor(int $schoolId, MessageEvent $event, ?MessageTemplate $override = null): string
    {
        $override ??= MessageTemplate::query()
            ->where('school_id', $schoolId)
            ->where('event', $event)
            ->first();

        return $override !== null && $override->is_active ? $override->body : $event->defaultBody();
    }

    public function update(School $school, MessageEvent $event, string $body, User $actor): MessageTemplate
    {
        return MessageTemplate::query()->updateOrCreate(
            ['school_id' => $school->id, 'event' => $event],
            ['body' => $body, 'is_active' => true, 'updated_by' => $actor->id],
        )->refresh();
    }

    /**
     * Drops the override so the event falls back to its shipped wording.
     */
    public function reset(School $school, MessageEvent $event): void
    {
        MessageTemplate::query()
            ->where('school_id', $school->id)
            ->where('event', $event)
            ->delete();
    }
}
