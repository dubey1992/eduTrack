<?php

namespace App\Http\Requests\StaffAttendance;

use App\Enums\StaffAttendanceStatus;
use App\Enums\UserRole;
use App\Http\Requests\Concerns\ChecksSchoolDates;
use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\Department;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class UpdateStaffAttendanceRequest extends FormRequest
{
    use ChecksSchoolDates;
    use ScopesSchool;

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
            'school_id' => $this->schoolIdRules(),
            'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')],
            'attendance_date' => ['required', 'date', $this->notInFuture()],
            'records' => [
                'required', 'array', 'min:1',
                function ($attribute, $value, $fail) {
                    $staffProfileIds = array_column($value, 'staff_profile_id');
                    if (count($staffProfileIds) !== count(array_unique($staffProfileIds))) {
                        $fail('Each staff member can only appear once in the attendance records.');
                    }
                },
            ],
            'records.*.staff_profile_id' => [
                'required', 'integer',
                Rule::exists('staff_profiles', 'id')->where(function ($query) {
                    $actor = $this->user();
                    $this->schoolScope()->applyTo($query, $this->requestedSchoolId());

                    // An HOD can only mark staff in the department(s) they
                    // head - never another department in the same school.
                    // This is a plain query builder (not Eloquent), so
                    // whereHas() isn't available here - a whereIn against
                    // their department ids does the same job.
                    if ($actor->role === UserRole::Hod) {
                        $query->whereIn(
                            'department_id',
                            Department::query()->where('hod_user_id', $actor->id)->pluck('id')
                        );
                    }
                }),
            ],
            'records.*.status' => ['required', new Enum(StaffAttendanceStatus::class)],
            'records.*.check_in' => ['nullable', 'date_format:H:i'],
            'records.*.check_out' => ['nullable', 'date_format:H:i'],
            'records.*.remarks' => ['nullable', 'string', 'max:255'],
        ];
    }
}
