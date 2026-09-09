<?php

namespace App\Http\Resources;

use App\Models\StaffAttendance;
use App\Support\WorkingHours;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin StaffAttendance
 */
class StaffAttendanceResource extends JsonResource
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
            'attendance_date' => $this->attendance_date->toDateString(),
            'status' => $this->status->value,
            'check_in' => $this->check_in ? substr($this->check_in, 0, 5) : null,
            'check_out' => $this->check_out ? substr($this->check_out, 0, 5) : null,
            'working_hours' => WorkingHours::format($this->check_in, $this->check_out),
            'remarks' => $this->remarks,
            'marked_by' => $this->marked_by,
            'marked_by_name' => $this->whenLoaded('markedBy', fn () => $this->markedBy?->name),
            'created_at' => $this->created_at,
        ];
    }
}
