<?php

namespace App\Http\Resources;

use App\Models\Department;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Department
 */
class DepartmentResource extends JsonResource
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
            'name' => $this->name,
            'hod_user_id' => $this->hod_user_id,
            'hod_name' => $this->whenLoaded('hod', fn () => $this->hod?->name),
            'created_at' => $this->created_at,
        ];
    }
}
