<?php

namespace App\Http\Resources;

use App\Models\StudentTransportAssignment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One rider on a route - the "Students on Bus" row from the prototype,
 * before any trip status exists (Phase 15 adds boarded/dropped).
 *
 * @mixin StudentTransportAssignment
 */
class RouteStudentResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $student = $this->student;
        $section = $student->classSection;

        return [
            'student_id' => $student->id,
            'admission_number' => $student->admission_number,
            'name' => $student->name,
            'class_section_name' => $section === null ? null : trim("{$section->schoolClass?->name} {$section->name}"),
            'guardian_name' => $student->guardian_name,
            'guardian_mobile' => $student->guardian_mobile,
            'stop_id' => $this->transport_stop_id,
            'stop_name' => $this->stop->name,
            'stop_sequence_number' => $this->stop->sequence_number,
        ];
    }
}
