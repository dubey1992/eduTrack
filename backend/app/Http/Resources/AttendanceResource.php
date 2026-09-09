<?php

namespace App\Http\Resources;

use App\Models\Attendance;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Attendance
 */
class AttendanceResource extends JsonResource
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
            'academic_year_id' => $this->academic_year_id,
            'class_section_id' => $this->class_section_id,
            'class_section_name' => $classSection && $classSection->relationLoaded('schoolClass')
                ? trim("{$classSection->schoolClass?->name} {$classSection->name}")
                : null,
            'student_id' => $this->student_id,
            'student_name' => $this->whenLoaded('student', fn () => $this->student?->name),
            'attendance_date' => $this->attendance_date->toDateString(),
            'status' => $this->status->value,
            'remarks' => $this->remarks,
            'marked_by' => $this->marked_by,
            'marked_by_name' => $this->whenLoaded('markedBy', fn () => $this->markedBy?->name),
            'created_at' => $this->created_at,
        ];
    }
}
