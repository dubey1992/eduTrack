<?php

namespace App\Http\Requests\Subjects;

use App\Enums\UserRole;
use App\Models\Subject;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class StoreSubjectRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Subject::class);
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
            'school_id' => $this->user()->role === UserRole::SuperAdmin
                ? ['required', 'integer', 'exists:schools,id']
                : ['nullable'],
            'department_id' => [
                'required', 'integer',
                Rule::exists('departments', 'id')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'code' => [
                'required', 'string', 'max:20',
                Rule::unique('subjects', 'code')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'name' => ['required', 'string', 'max:100'],
            'min_class_level' => ['required', 'integer', 'min:0', 'max:12'],
            'max_class_level' => ['required', 'integer', 'min:0', 'max:12'],
            'lead_teacher_id' => [
                'nullable', 'integer',
                Rule::exists('users', 'id')->where(function ($query) {
                    $query->where('school_id', $this->resolvedSchoolId())
                        ->whereIn('role', [UserRole::Hod->value, UserRole::Teacher->value]);
                }),
            ],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator) {
            if ($this->filled('min_class_level') && $this->filled('max_class_level')
                && $this->integer('max_class_level') < $this->integer('min_class_level')) {
                $validator->errors()->add('max_class_level', 'The max class level must be at or above the min class level.');
            }
        });
    }

    private function resolvedSchoolId(): ?int
    {
        return $this->user()->role === UserRole::SuperAdmin
            ? $this->integer('school_id')
            : $this->user()->school_id;
    }
}
