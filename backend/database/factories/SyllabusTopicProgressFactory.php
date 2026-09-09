<?php

namespace Database\Factories;

use App\Models\ClassSection;
use App\Models\SyllabusTopic;
use App\Models\SyllabusTopicProgress;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<SyllabusTopicProgress>
 */
class SyllabusTopicProgressFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $topic = SyllabusTopic::factory()->create();

        return [
            'school_id' => $topic->school_id,
            'syllabus_topic_id' => $topic->id,
            'class_section_id' => ClassSection::factory(),
            'completed_by' => User::factory(),
            'completed_at' => now(),
        ];
    }

    public function forTopic(SyllabusTopic $topic): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $topic->school_id,
            'syllabus_topic_id' => $topic->id,
        ]);
    }

    public function forSection(ClassSection $section): static
    {
        return $this->state(fn (array $attributes) => ['class_section_id' => $section->id]);
    }

    public function completedBy(User $user): static
    {
        return $this->state(fn (array $attributes) => ['completed_by' => $user->id]);
    }
}
