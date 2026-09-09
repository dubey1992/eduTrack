<?php

namespace App\Http\Resources;

use App\Models\ClassSection;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin ClassSection
 */
class ClassSectionResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'school_class_id' => $this->school_class_id,
            'name' => $this->name,
            'room_number' => $this->room_number,
            'class_teacher_id' => $this->class_teacher_id,
            'class_teacher_name' => $this->whenLoaded('classTeacher', fn () => $this->classTeacher?->name),
        ];
    }
}
