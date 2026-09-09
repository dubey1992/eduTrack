<?php

namespace Database\Factories;

use App\Models\ClassSection;
use App\Models\SchoolClass;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<ClassSection>
 */
class ClassSectionFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_class_id' => SchoolClass::factory(),
            'name' => fake()->randomElement(['A', 'B', 'C', 'D']),
            'room_number' => fake()->bothify('Room ###'),
            'class_teacher_id' => null,
        ];
    }

    public function forClass(SchoolClass $schoolClass): static
    {
        return $this->state(fn (array $attributes) => ['school_class_id' => $schoolClass->id]);
    }

    public function withClassTeacher(User $teacher): static
    {
        return $this->state(fn (array $attributes) => ['class_teacher_id' => $teacher->id]);
    }
}
