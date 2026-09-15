<?php

namespace App\Http\Requests\Departments;

use App\Enums\UserRole;
use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\Department;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreDepartmentRequest extends FormRequest
{
    use ScopesSchool;

    public function authorize(): bool
    {
        return $this->user()->can('create', Department::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // The real client always sends this key - literal null for a
            // non-SuperAdmin, since school_id is taken from the actor's own
            // account server-side either way (see resolvedSchoolId()) -
            // so non-SuperAdmin gets its own minimal, null-tolerant rule set
            // rather than the full integer/exists check meant for SuperAdmin.
            'school_id' => $this->schoolIdRules(),
            'name' => [
                'required', 'string', 'max:100',
                Rule::unique('departments', 'name')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'hod_user_id' => [
                'nullable', 'integer',
                Rule::exists('users', 'id')->where(function ($query) {
                    $query->where('school_id', $this->resolvedSchoolId())
                        ->whereIn('role', [UserRole::Hod->value, UserRole::Teacher->value]);
                }),
            ],
        ];
    }
}
