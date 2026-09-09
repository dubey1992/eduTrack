<?php

namespace App\Http\Resources;

use App\Models\DailyTeachingReport;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin DailyTeachingReport
 */
class DailyTeachingReportResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $entry = $this->timetableEntry;
        $classSection = $entry?->classSection;

        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'timetable_entry_id' => $this->timetable_entry_id,
            'class_section_name' => $this->whenLoaded(
                'timetableEntry',
                fn () => $classSection ? "{$classSection->schoolClass->name} {$classSection->name}" : null
            ),
            'period_number' => $this->whenLoaded('timetableEntry', fn () => $entry?->period?->period_number),
            'subject_name' => $this->whenLoaded('timetableEntry', fn () => $entry?->subject?->name),
            'teacher_id' => $this->teacher_id,
            'teacher_name' => $this->whenLoaded('teacher', fn () => $this->teacher?->name),
            'report_date' => $this->report_date->toDateString(),
            'topic_taught' => $this->topic_taught,
            'homework' => $this->homework,
            'remarks' => $this->remarks,
            'reviewed_by' => $this->reviewed_by,
            'reviewed_by_name' => $this->whenLoaded('reviewedBy', fn () => $this->reviewedBy?->name),
            'reviewed_at' => $this->reviewed_at,
        ];
    }
}
