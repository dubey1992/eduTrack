<?php

namespace Database\Factories;

use App\Enums\UserRole;
use App\Models\Department;
use App\Models\School;
use App\Models\StaffProfile;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<StaffProfile>
 */
class StaffProfileFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'user_id' => User::factory()->role(UserRole::Teacher),
            'school_id' => School::factory(),
            'employee_id' => strtoupper(fake()->unique()->bothify('EMP-####')),
            'department_id' => null,
            'designation' => null,
            'joining_date' => fake()->dateTimeBetween('-5 years', 'now')->format('Y-m-d'),
            'address' => fake()->address(),
        ];
    }

    public function forUser(User $user): static
    {
        return $this->state(fn (array $attributes) => [
            'user_id' => $user->id,
            'school_id' => $user->school_id,
        ]);
    }

    public function forDepartment(Department $department): static
    {
        return $this->state(fn (array $attributes) => ['department_id' => $department->id]);
    }
}
