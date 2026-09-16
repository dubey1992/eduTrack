<?php

namespace App\Http\Requests\Users;

use App\Enums\UserRole;
use App\Http\Requests\Concerns\LowercasesEmail;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class UpdateUserRequest extends FormRequest
{
    use LowercasesEmail;

    private const SCHOOL_ADMIN_ASSIGNABLE_ROLES = [
        UserRole::Hod, UserRole::Teacher, UserRole::Staff, UserRole::TransportManager,
    ];

    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('user'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $userId = $this->route('user')->id;
        $actor = $this->user();

        return [
            'first_name' => ['sometimes', 'required', 'string', 'max:100'],
            'last_name' => ['sometimes', 'required', 'string', 'max:100'],
            'email' => ['sometimes', 'required', 'email', Rule::unique('users', 'email')->ignore($userId)],
            'mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'password' => ['sometimes', 'required', 'string', 'min:8'],
            'role' => [
                'sometimes', 'required', new Enum(UserRole::class),
                function (string $attribute, mixed $value, Closure $fail) use ($actor) {
                    if (
                        $actor->role === UserRole::SchoolAdmin
                        && ! in_array($value, array_column(self::SCHOOL_ADMIN_ASSIGNABLE_ROLES, 'value'), true)
                    ) {
                        $fail('A school admin can only assign the HOD, Teacher, Staff, or Transport Manager role.');
                    }
                },
            ],
            // Moving a user between schools isn't a feature yet - school_id
            // is deliberately not editable through this endpoint.
        ];
    }
}
