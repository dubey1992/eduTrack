<?php

namespace Database\Factories;

use App\Models\School;
use App\Models\Subject;
use App\Models\SyllabusTopic;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<SyllabusTopic>
 */
class SyllabusTopicFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'subject_id' => Subject::factory(),
            'title' => 'Chapter '.fake()->unique()->numberBetween(1, 999).': '.fake()->words(3, true),
            'sequence_number' => fake()->unique()->numberBetween(1, 999),
        ];
    }

    public function forSubject(Subject $subject): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $subject->school_id,
            'subject_id' => $subject->id,
        ]);
    }

    public function atSequence(int $sequenceNumber): static
    {
        return $this->state(fn (array $attributes) => ['sequence_number' => $sequenceNumber]);
    }
}
