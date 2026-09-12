<?php

namespace Database\Factories;

use App\Models\Student;
use App\Models\StudentTransportAssignment;
use App\Models\TransportStop;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<StudentTransportAssignment>
 */
class StudentTransportAssignmentFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'transport_stop_id' => TransportStop::factory(),
            'school_id' => fn (array $attributes) => $this->stop($attributes)->school_id,
            'route_id' => fn (array $attributes) => $this->stop($attributes)->route_id,
            'student_id' => Student::factory(),
        ];
    }

    /**
     * @param  array<string, mixed>  $attributes
     */
    private function stop(array $attributes): TransportStop
    {
        return TransportStop::findOrFail($attributes['transport_stop_id']);
    }

    public function forStudent(Student $student): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $student->school_id, 'student_id' => $student->id]);
    }

    public function atStop(TransportStop $stop): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $stop->school_id,
            'route_id' => $stop->route_id,
            'transport_stop_id' => $stop->id,
        ]);
    }
}
