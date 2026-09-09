<?php

namespace App\Http\Requests\Departments;

use App\Enums\UserRole;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateDepartmentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('department'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $department = $this->route('department');

        return [
            'name' => [
                'sometimes', 'required', 'string', 'max:100',
                Rule::unique('departments', 'name')
                    ->where(fn ($query) => $query->where('school_id', $department->school_id))
                    ->ignore($department->id),
            ],
            'hod_user_id' => [
                'nullable', 'integer',
                Rule::exists('users', 'id')->where(function ($query) use ($department) {
                    $query->where('school_id', $department->school_id)
                        ->whereIn('role', [UserRole::Hod->value, UserRole::Teacher->value]);
                }),
            ],
        ];
    }
}
