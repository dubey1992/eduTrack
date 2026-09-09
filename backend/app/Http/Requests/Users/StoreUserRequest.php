<?php

namespace App\Http\Requests\Users;

use App\Enums\UserRole;
use App\Models\User;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class StoreUserRequest extends FormRequest
{
    /**
     * Roles a SCHOOL_ADMIN is allowed to create - never another admin.
     */
    private const SCHOOL_ADMIN_ASSIGNABLE_ROLES = [
        UserRole::Hod, UserRole::Teacher, UserRole::Staff, UserRole::TransportManager,
    ];

    public function authorize(): bool
    {
        return $this->user()->can('create', User::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $actor = $this->user();

        return [
            'first_name' => ['required', 'string', 'max:100'],
            'last_name' => ['required', 'string', 'max:100'],
            'email' => ['required', 'email', Rule::unique('users', 'email')],
            // Multi-nation users always carry a dial code - e.g. "+91 9876543210".
            'mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'password' => ['required', 'string', 'min:8'],
            'role' => [
                'required',
                new Enum(UserRole::class),
                function (string $attribute, mixed $value, Closure $fail) use ($actor) {
                    if (
                        $actor->role === UserRole::SchoolAdmin
                        && ! in_array($value, array_column(self::SCHOOL_ADMIN_ASSIGNABLE_ROLES, 'value'), true)
                    ) {
                        $fail('A school admin can only create HOD, Teacher, Staff, or Transport Manager accounts.');
                    }
                },
            ],
            // A SCHOOL_ADMIN's school_id is always taken from their own
            // account server-side (see UserService::create) - never from
            // this field - so it only needs real validation for SUPER_ADMIN.
            'school_id' => $actor->role === UserRole::SuperAdmin
                ? [
                    Rule::requiredIf(fn () => $this->input('role') !== UserRole::SuperAdmin->value),
                    'nullable', 'integer', 'exists:schools,id',
                ]
                : ['nullable'],
        ];
    }
}
