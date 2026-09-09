<?php

namespace App\Http\Resources;

use App\Models\SchoolClass;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin SchoolClass
 */
class SchoolClassResource extends JsonResource
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
            'academic_year_id' => $this->academic_year_id,
            'academic_year_name' => $this->whenLoaded('academicYear', fn () => $this->academicYear->name),
            'name' => $this->name,
            'level' => $this->level,
            'sections' => ClassSectionResource::collection($this->whenLoaded('sections')),
            'created_at' => $this->created_at,
        ];
    }
}
