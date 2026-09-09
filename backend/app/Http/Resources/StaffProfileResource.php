<?php

namespace App\Http\Resources;

use App\Models\StaffProfile;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin StaffProfile
 */
class StaffProfileResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $user = $this->user;

        return [
            'id' => $this->id,
            'user_id' => $this->user_id,
            'employee_id' => $this->employee_id,
            'first_name' => $user->first_name,
            'last_name' => $user->last_name,
            'name' => $user->name,
            'email' => $user->email,
            'mobile' => $user->mobile,
            'role' => $user->role->value,
            'status' => $user->status->value,
            'school_id' => $this->school_id,
            'school_name' => $this->whenLoaded('school', fn () => $this->school?->name),
            'department_id' => $this->department_id,
            'department_name' => $this->whenLoaded('department', fn () => $this->department?->name),
            'designation' => $this->designation,
            'joining_date' => $this->joining_date->toDateString(),
            'address' => $this->address,
            // "Assigned classes" the prototype shows on this screen -
            // derived from Phase 4's class_teacher_id, not a new table.
            'class_teacher_of' => $user->relationLoaded('classTeacherOf')
                ? $user->classTeacherOf->map(fn ($section) => $section->relationLoaded('schoolClass')
                    ? trim("{$section->schoolClass?->name} {$section->name}")
                    : $section->name)->values()
                : [],
        ];
    }
}
