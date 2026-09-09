<?php

namespace App\Http\Resources;

use App\Models\TimetableEntry;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin TimetableEntry
 */
class TimetableEntryResource extends JsonResource
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
            'class_section_id' => $this->class_section_id,
            'class_section_name' => $this->whenLoaded(
                'classSection',
                fn () => $classSection ? "{$classSection->schoolClass->name} {$classSection->name}" : null
            ),
            'period_id' => $this->period_id,
            'period_number' => $this->whenLoaded('period', fn () => $this->period?->period_number),
            'day_of_week' => $this->day_of_week->value,
            'subject_id' => $this->subject_id,
            'subject_name' => $this->whenLoaded('subject', fn () => $this->subject?->name),
            'teacher_id' => $this->teacher_id,
            'teacher_name' => $this->whenLoaded('teacher', fn () => $this->teacher?->name),
        ];
    }
}
