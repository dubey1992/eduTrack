<?php

namespace Database\Factories;

use App\Models\Student;
use App\Models\TransportStop;
use App\Models\TransportTrip;
use App\Models\TransportTripRider;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<TransportTripRider>
 */
class TransportTripRiderFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'trip_id' => TransportTrip::factory(),
            'student_id' => Student::factory(),
            'stop_id' => fn () => TransportStop::factory()->create()->id,
            'stop_name' => fn (array $attributes) => $this->stop($attributes)?->name,
            'stop_sequence_number' => fn (array $attributes) => $this->stop($attributes)?->sequence_number,
            'status' => 'pending',
            'boarded_at' => null,
            'dropped_at' => null,
        ];
    }

    /**
     * @param  array<string, mixed>  $attributes
     */
    private function stop(array $attributes): ?TransportStop
    {
        return $attributes['stop_id'] === null ? null : TransportStop::findOrFail($attributes['stop_id']);
    }

    public function forTrip(TransportTrip $trip): static
    {
        return $this->state(fn (array $attributes) => ['trip_id' => $trip->id]);
    }

    public function forStudent(Student $student): static
    {
        return $this->state(fn (array $attributes) => ['student_id' => $student->id]);
    }

    public function atStop(TransportStop $stop): static
    {
        return $this->state(fn (array $attributes) => [
            'stop_id' => $stop->id,
            'stop_name' => $stop->name,
            'stop_sequence_number' => $stop->sequence_number,
        ]);
    }

    public function status(string $status): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => $status,
            'boarded_at' => in_array($status, ['boarded', 'dropped'], true) ? now() : null,
            'dropped_at' => $status === 'dropped' ? now() : null,
        ]);
    }
}
