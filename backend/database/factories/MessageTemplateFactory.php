<?php

namespace Database\Factories;

use App\Enums\MessageEvent;
use App\Models\MessageTemplate;
use App\Models\School;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<MessageTemplate>
 */
class MessageTemplateFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'event' => MessageEvent::AttendanceAbsent,
            'body' => '{student_name} was absent today.',
            'is_active' => true,
            'updated_by' => null,
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function forEvent(MessageEvent $event): static
    {
        return $this->state(fn (array $attributes) => ['event' => $event]);
    }

    public function body(string $body): static
    {
        return $this->state(fn (array $attributes) => ['body' => $body]);
    }
}
