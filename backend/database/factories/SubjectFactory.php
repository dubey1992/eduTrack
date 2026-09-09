<?php

namespace Database\Factories;

use App\Models\Department;
use App\Models\School;
use App\Models\Subject;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Subject>
 */
class SubjectFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'department_id' => Department::factory(),
            'code' => strtoupper(fake()->unique()->lexify('???')),
            'name' => fake()->randomElement(['Mathematics', 'Science', 'English', 'History', 'Geography']),
            'min_class_level' => 1,
            'max_class_level' => 10,
            'lead_teacher_id' => null,
        ];
    }

    public function forDepartment(Department $department): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $department->school_id,
            'department_id' => $department->id,
        ]);
    }

    public function withLeadTeacher(User $teacher): static
    {
        return $this->state(fn (array $attributes) => ['lead_teacher_id' => $teacher->id]);
    }
}
