<?php

namespace Database\Factories;

use App\Models\DailyTeachingReport;
use App\Models\TimetableEntry;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<DailyTeachingReport>
 */
class DailyTeachingReportFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $entry = TimetableEntry::factory()->create();

        return [
            'school_id' => $entry->school_id,
            'timetable_entry_id' => $entry->id,
            'teacher_id' => $entry->teacher_id,
            'report_date' => now()->toDateString(),
            'topic_taught' => fake()->sentence(4),
            'homework' => fake()->sentence(6),
            'remarks' => null,
            'reviewed_by' => null,
            'reviewed_at' => null,
        ];
    }

    public function forEntry(TimetableEntry $entry): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $entry->school_id,
            'timetable_entry_id' => $entry->id,
            'teacher_id' => $entry->teacher_id,
        ]);
    }

    public function onDate(string $date): static
    {
        return $this->state(fn (array $attributes) => ['report_date' => $date]);
    }

    public function reviewed(int $reviewerId): static
    {
        return $this->state(fn (array $attributes) => [
            'reviewed_by' => $reviewerId,
            'reviewed_at' => now(),
        ]);
    }
}
