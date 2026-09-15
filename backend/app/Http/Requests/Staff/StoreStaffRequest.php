<?php

namespace App\Http\Requests\Staff;

use App\Enums\UserRole;
use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\StaffProfile;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class StoreStaffRequest extends FormRequest
{
    use ScopesSchool;

    /**
     * Unlike the generic Users feature (StoreUserRequest), this form is
     * specifically "add an employee" - it never creates an admin account,
     * regardless of who the actor is.
     */
    private const STAFF_ROLES = [UserRole::Hod, UserRole::Teacher, UserRole::Staff, UserRole::TransportManager];

    public function authorize(): bool
    {
        return $this->user()->can('create', StaffProfile::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'first_name' => ['required', 'string', 'max:100'],
            'last_name' => ['required', 'string', 'max:100'],
            'email' => ['required', 'email', Rule::unique('users', 'email')],
            'mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'password' => ['required', 'string', 'min:8'],
            'role' => ['required', new Enum(UserRole::class), Rule::in(self::STAFF_ROLES)],
            // The real client always sends this key - literal null for a
            // non-SuperAdmin, since school_id is taken from the actor's own
            // account server-side either way (see resolvedSchoolId()) -
            // so non-SuperAdmin gets its own minimal, null-tolerant rule set
            // rather than the full integer/exists check meant for SuperAdmin.
            'school_id' => $this->schoolIdRules(),
            'employee_id' => [
                'required', 'string', 'max:30',
                Rule::unique('staff_profiles', 'employee_id')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'department_id' => [
                'nullable', 'integer',
                Rule::exists('departments', 'id')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'designation' => ['nullable', 'string', 'max:100'],
            'joining_date' => ['required', 'date'],
            'address' => ['nullable', 'string', 'max:500'],
        ];
    }

    /**
     * The subset of validated() that goes to UserService::create().
     *
     * @return array<string, mixed>
     */
    public function userData(): array
    {
        return $this->safe()->only(['first_name', 'last_name', 'email', 'mobile', 'password', 'role', 'school_id']);
    }

    /**
     * The subset of validated() that goes onto the StaffProfile.
     *
     * @return array<string, mixed>
     */
    public function profileData(): array
    {
        return $this->safe()->only(['employee_id', 'department_id', 'designation', 'joining_date', 'address']);
    }
}
