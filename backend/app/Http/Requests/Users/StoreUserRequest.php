<?php

namespace App\Http\Requests\Users;

use App\Enums\UserRole;
use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\School;
use App\Models\User;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;
use Illuminate\Validation\Validator;

/**
 * Onboards an admin-tier account - the only role this endpoint creates is
 * SCHOOL_ADMIN (see UserPolicy::create()). Whether the result is a "School
 * Admin" or a "Sub Admin" depends on who's creating it, not on anything in
 * this request - UserService::create() derives that from the actor.
 * Operational staff roles go through Teachers & Staff instead, which
 * creates the StaffProfile alongside the login that this screen
 * deliberately doesn't.
 */
class StoreUserRequest extends FormRequest
{
    use ScopesSchool;

    public function authorize(): bool
    {
        return $this->user()->can('create', User::class);
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
            // Multi-nation users always carry a dial code - e.g. "+91 9876543210".
            'mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'password' => ['required', 'string', 'min:8'],
            // A Super Admin also onboards the group-level role; a School or
            // Group Admin creating an account below them only ever makes a
            // School Admin (a "Sub Admin" - see UserService::create()).
            'role' => [
                'required',
                new Enum(UserRole::class),
                Rule::in($this->user()->role === UserRole::SuperAdmin
                    ? [UserRole::SchoolAdmin->value, UserRole::GroupAdmin->value]
                    : [UserRole::SchoolAdmin->value]),
            ],
            // Anybody who answers for more than one school must pick one
            // explicitly - a SUPER_ADMIN, and an admin of a school in a
            // group. An admin of a standalone school is scoped to it
            // server-side (see UserService::create()) and need not say.
            // Never trusted from this field in either case.
            'school_id' => $this->schoolIdRules(),
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator) {
            if ($this->input('role') !== UserRole::GroupAdmin->value) {
                return;
            }

            $school = School::query()->find($this->resolvedSchoolId());

            // A group admin sits at the parent and answers for the branches
            // beneath it. Attaching one to a branch would be claiming the
            // branch is the group.
            if ($school !== null && $school->isBranch()) {
                $validator->errors()->add(
                    'school_id',
                    "\"{$school->name}\" is a branch. A Group Admin belongs to the school the branches sit under.",
                );
            }
        });
    }
}
