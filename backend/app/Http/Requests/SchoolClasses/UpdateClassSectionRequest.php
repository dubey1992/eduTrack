<?php

namespace App\Http\Requests\SchoolClasses;

use App\Enums\UserRole;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateClassSectionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('section'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $section = $this->route('section');

        return [
            'name' => [
                'sometimes', 'required', 'string', 'max:10',
                Rule::unique('class_sections', 'name')
                    ->where(fn ($query) => $query->where('school_class_id', $section->school_class_id))
                    ->ignore($section->id),
            ],
            'room_number' => ['nullable', 'string', 'max:20'],
            'class_teacher_id' => [
                'nullable', 'integer',
                Rule::exists('users', 'id')->where(function ($query) use ($section) {
                    $query->where('school_id', $section->schoolClass->school_id)
                        ->whereIn('role', [UserRole::Hod->value, UserRole::Teacher->value]);
                }),
            ],
        ];
    }
}
