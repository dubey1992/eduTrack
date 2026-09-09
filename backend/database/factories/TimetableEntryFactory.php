<?php

namespace Database\Factories;

use App\Models\ClassSection;
use App\Models\Period;
use App\Models\Subject;
use App\Models\TimetableEntry;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<TimetableEntry>
 */
class TimetableEntryFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $classSection = ClassSection::factory()->create();

        return [
            'school_id' => $classSection->schoolClass->school_id,
            'class_section_id' => $classSection->id,
            'period_id' => Period::factory()->forSchool($classSection->schoolClass->school),
            'day_of_week' => 'monday',
            'subject_id' => Subject::factory(),
            'teacher_id' => User::factory(),
        ];
    }

    public function forClassSection(ClassSection $classSection): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $classSection->schoolClass->school_id,
            'class_section_id' => $classSection->id,
        ]);
    }

    public function forPeriod(Period $period): static
    {
        return $this->state(fn (array $attributes) => ['period_id' => $period->id]);
    }

    public function onDay(string $day): static
    {
        return $this->state(fn (array $attributes) => ['day_of_week' => $day]);
    }

    public function forSubject(Subject $subject): static
    {
        return $this->state(fn (array $attributes) => ['subject_id' => $subject->id]);
    }

    public function forTeacher(User $teacher): static
    {
        return $this->state(fn (array $attributes) => ['teacher_id' => $teacher->id]);
    }
}
