<?php

namespace App\Http\Requests\Hod;

use App\Enums\UserRole;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class HodDepartmentReportRequest extends FormRequest
{
    /**
     * Role/department authorization happens in the controller via
     * DepartmentPolicy once the ids are known to be real (422 for a bad id,
     * 403 for a real one the actor may not see) - same split as
     * StaffAttendanceRegisterRequest.
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
            'school_id' => $this->user()->role === UserRole::SuperAdmin
                ? ['required', 'integer', Rule::exists('schools', 'id')]
                : ['nullable'],
            'department_id' => [
                'nullable',
                'integer',
                Rule::exists('departments', 'id')->where('school_id', $this->resolvedSchoolId()),
            ],
            'month' => ['nullable', 'date_format:Y-m'],
        ];
    }

    private function resolvedSchoolId(): ?int
    {
        $actor = $this->user();

        return $actor->role === UserRole::SuperAdmin ? (int) $this->input('school_id') : $actor->school_id;
    }
}
