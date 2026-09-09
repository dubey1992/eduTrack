<?php

namespace Database\Factories;

use App\Models\Attendance;
use App\Models\ClassSection;
use App\Models\Student;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Attendance>
 */
class AttendanceFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $student = Student::factory()->create();

        return [
            'school_id' => $student->school_id,
            'academic_year_id' => $student->classSection?->schoolClass->academic_year_id,
            'class_section_id' => $student->class_section_id,
            'student_id' => $student->id,
            'attendance_date' => now()->toDateString(),
            'status' => 'present',
            'remarks' => null,
            'marked_by' => null,
        ];
    }

    public function forStudent(Student $student): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $student->school_id,
            'academic_year_id' => $student->classSection?->schoolClass->academic_year_id,
            'class_section_id' => $student->class_section_id,
            'student_id' => $student->id,
        ]);
    }

    public function forSection(ClassSection $section): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $section->schoolClass->school_id,
            'academic_year_id' => $section->schoolClass->academic_year_id,
            'class_section_id' => $section->id,
        ]);
    }

    public function onDate(string $date): static
    {
        return $this->state(fn (array $attributes) => ['attendance_date' => $date]);
    }

    public function status(string $status): static
    {
        return $this->state(fn (array $attributes) => ['status' => $status]);
    }
}
