<?php

namespace App\Http\Requests\StaffAttendance;

use App\Http\Requests\Concerns\ChecksSchoolDates;
use App\Http\Requests\Concerns\ScopesSchool;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StaffAttendanceRegisterRequest extends FormRequest
{
    use ChecksSchoolDates;
    use ScopesSchool;

    /**
     * school_id arrives as a query param, not a route-bound model, so
     * there's nothing to check ownership of until after `rules()` confirms
     * it's a real id - a bad/missing id should fail validation (422), not
     * authorization (403). The controller does the actual
     * StaffAttendancePolicy::manage check once the school is loaded.
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
            // A SUPER_ADMIN must pick a school explicitly; every other role
            // is always scoped to their own (see StaffAttendanceController).
            'school_id' => $this->schoolIdRules(),
            'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')],
            'date' => ['required', 'date', $this->notInFuture()],
        ];
    }
}
