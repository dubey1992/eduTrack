<?php

namespace App\Http\Requests\Users;

use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

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
            'role' => ['required', new Enum(UserRole::class), Rule::in([UserRole::SchoolAdmin->value])],
            // A SUPER_ADMIN actor must pick a school explicitly; a School
            // Admin actor creating a Sub Admin is always scoped to their
            // own school server-side (see UserService::create()) - never
            // trusted from this field either way.
            'school_id' => $this->user()->role === UserRole::SuperAdmin
                ? ['required', 'integer', 'exists:schools,id']
                : ['nullable'],
        ];
    }
}
