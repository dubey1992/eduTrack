<?php

namespace App\Http\Resources;

use App\Models\TransportTripRider;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin TransportTripRider
 */
class TripRiderResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $student = $this->student;
        $section = $student->classSection;

        return [
            'student_id' => $this->student_id,
            'admission_number' => $student->admission_number,
            'name' => $student->name,
            'class_section_name' => $section === null ? null : trim("{$section->schoolClass?->name} {$section->name}"),
            'guardian_name' => $student->guardian_name,
            'guardian_mobile' => $student->guardian_mobile,
            'stop_id' => $this->stop_id,
            'stop_name' => $this->stop_name,
            'stop_sequence_number' => $this->stop_sequence_number,
            'status' => $this->status->value,
            'boarded_at' => $this->boarded_at,
            'dropped_at' => $this->dropped_at,
        ];
    }
}
