<?php

namespace App\Http\Resources;

use App\Models\Student;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Student
 */
class StudentResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $classSection = $this->classSection;

        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'school_name' => $this->whenLoaded('school', fn () => $this->school?->name),
            'class_section_id' => $this->class_section_id,
            'class_section_name' => $classSection && $classSection->relationLoaded('schoolClass')
                ? trim("{$classSection->schoolClass?->name} {$classSection->name}")
                : null,
            'admission_number' => $this->admission_number,
            'first_name' => $this->first_name,
            'last_name' => $this->last_name,
            'name' => $this->name,
            'roll_number' => $this->roll_number,
            'guardian_name' => $this->guardian_name,
            'guardian_mobile' => $this->guardian_mobile,
            'address' => $this->address,
            'status' => $this->status->value,
            'transport' => $this->whenLoaded('transportAssignment', function () {
                $assignment = $this->transportAssignment;
                if ($assignment === null) {
                    return null;
                }

                return [
                    'route_id' => $assignment->route_id,
                    'route_name' => $assignment->route->name,
                    'route_label' => $assignment->route->label(),
                    'vehicle_name' => $assignment->route->vehicle?->name,
                    'stop_id' => $assignment->transport_stop_id,
                    'stop_name' => $assignment->stop->name,
                ];
            }),
            'created_at' => $this->created_at,
        ];
    }
}
