<?php

namespace App\Http\Resources;

use App\Models\StaffLeave;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin StaffLeave
 */
class StaffLeaveResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $staffProfile = $this->staffProfile;

        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'staff_profile_id' => $this->staff_profile_id,
            'employee_id' => $staffProfile?->employee_id,
            'staff_name' => $this->whenLoaded('staffProfile', fn () => $staffProfile?->user?->name),
            'department_name' => $this->whenLoaded('staffProfile', fn () => $staffProfile?->department?->name),
            'leave_type' => $this->leave_type->value,
            'start_date' => $this->start_date->toDateString(),
            'end_date' => $this->end_date->toDateString(),
            'reason' => $this->reason,
            'status' => $this->status->value,
            'applied_by_name' => $this->whenLoaded('appliedBy', fn () => $this->appliedBy?->name),
            'reviewed_by_name' => $this->whenLoaded('reviewedBy', fn () => $this->reviewedBy?->name),
            'review_remarks' => $this->review_remarks,
            'created_at' => $this->created_at,
        ];
    }
}
