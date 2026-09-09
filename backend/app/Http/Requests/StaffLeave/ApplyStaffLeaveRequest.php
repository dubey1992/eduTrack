<?php

namespace App\Http\Requests\StaffLeave;

use App\Enums\LeaveType;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rules\Enum;

class ApplyStaffLeaveRequest extends FormRequest
{
    /**
     * The StaffLeavePolicy::apply check happens in the controller via
     * Gate::authorize(), same split as StaffAttendance's requests - a
     * missing/invalid field fails validation (422), not authorization.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'leave_type' => ['required', new Enum(LeaveType::class)],
            'start_date' => ['required', 'date'],
            'end_date' => ['required', 'date', 'after_or_equal:start_date'],
            'reason' => ['required', 'string', 'max:500'],
        ];
    }
}
