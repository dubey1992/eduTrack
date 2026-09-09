<?php

namespace App\Http\Requests\Subjects;

use App\Enums\UserRole;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class UpdateSubjectRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('subject'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $subject = $this->route('subject');

        return [
            // school_id is fixed at creation, same as Payment's pattern.
            'department_id' => [
                'sometimes', 'required', 'integer',
                Rule::exists('departments', 'id')->where(fn ($query) => $query->where('school_id', $subject->school_id)),
            ],
            'code' => [
                'sometimes', 'required', 'string', 'max:20',
                Rule::unique('subjects', 'code')
                    ->where(fn ($query) => $query->where('school_id', $subject->school_id))
                    ->ignore($subject->id),
            ],
            'name' => ['sometimes', 'required', 'string', 'max:100'],
            'min_class_level' => ['sometimes', 'required', 'integer', 'min:0', 'max:12'],
            'max_class_level' => ['sometimes', 'required', 'integer', 'min:0', 'max:12'],
            'lead_teacher_id' => [
                'nullable', 'integer',
                Rule::exists('users', 'id')->where(function ($query) use ($subject) {
                    $query->where('school_id', $subject->school_id)
                        ->whereIn('role', [UserRole::Hod->value, UserRole::Teacher->value]);
                }),
            ],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator) {
            $subject = $this->route('subject');
            $min = $this->input('min_class_level', $subject->min_class_level);
            $max = $this->input('max_class_level', $subject->max_class_level);

            if ($max < $min) {
                $validator->errors()->add('max_class_level', 'The max class level must be at or above the min class level.');
            }
        });
    }
}
