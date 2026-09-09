<?php

namespace Database\Factories;

use App\Models\Department;
use App\Models\School;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Department>
 */
class DepartmentFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'name' => fake()->unique()->randomElement([
                'Mathematics', 'Science', 'English', 'Social Studies', 'Computer Science', 'Administration',
            ]),
            'hod_user_id' => null,
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function withHod(User $hod): static
    {
        return $this->state(fn (array $attributes) => ['hod_user_id' => $hod->id]);
    }
}
