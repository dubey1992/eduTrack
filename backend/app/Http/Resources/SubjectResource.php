<?php

namespace App\Http\Resources;

use App\Models\Subject;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Subject
 */
class SubjectResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'school_name' => $this->whenLoaded('school', fn () => $this->school->name),
            'department_id' => $this->department_id,
            'department_name' => $this->whenLoaded('department', fn () => $this->department->name),
            'code' => $this->code,
            'name' => $this->name,
            'min_class_level' => $this->min_class_level,
            'max_class_level' => $this->max_class_level,
            'lead_teacher_id' => $this->lead_teacher_id,
            'lead_teacher_name' => $this->whenLoaded('leadTeacher', fn () => $this->leadTeacher?->name),
            'created_at' => $this->created_at,
        ];
    }
}
