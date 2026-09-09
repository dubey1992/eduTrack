<?php

namespace Database\Factories;

use App\Models\ClassSection;
use App\Models\School;
use App\Models\Student;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Student>
 */
class StudentFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'class_section_id' => ClassSection::factory(),
            'admission_number' => strtoupper('STU-'.fake()->unique()->numerify('####')),
            'first_name' => fake()->firstName(),
            'last_name' => fake()->lastName(),
            'roll_number' => (string) fake()->numberBetween(1, 50),
            'guardian_name' => fake()->name(),
            'guardian_mobile' => fake()->numerify('+91 ##########'),
            'address' => fake()->address(),
            'status' => 'active',
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function forSection(ClassSection $section): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $section->schoolClass->school_id,
            'class_section_id' => $section->id,
        ]);
    }

    public function inactive(): static
    {
        return $this->state(fn (array $attributes) => ['status' => 'inactive']);
    }
}
