<?php

namespace App\Http\Requests\Staff;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateStaffProfileRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('staffProfile'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $staffProfile = $this->route('staffProfile');

        return [
            // The account itself (name/email/password/role) is edited via
            // the existing /users endpoints, not duplicated here.
            'employee_id' => [
                'sometimes', 'required', 'string', 'max:30',
                Rule::unique('staff_profiles', 'employee_id')
                    ->where(fn ($query) => $query->where('school_id', $staffProfile->school_id))
                    ->ignore($staffProfile->id),
            ],
            'department_id' => [
                'nullable', 'integer',
                Rule::exists('departments', 'id')->where(fn ($query) => $query->where('school_id', $staffProfile->school_id)),
            ],
            'designation' => ['nullable', 'string', 'max:100'],
            'joining_date' => ['sometimes', 'required', 'date'],
            'address' => ['nullable', 'string', 'max:500'],
        ];
    }
}
