<?php

namespace App\Http\Requests\SchoolClasses;

use App\Enums\UserRole;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreClassSectionRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Adding a section is managing the parent class it belongs to.
        return $this->user()->can('update', $this->route('schoolClass'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $schoolClass = $this->route('schoolClass');

        return [
            'name' => [
                'required', 'string', 'max:10',
                Rule::unique('class_sections', 'name')->where(fn ($query) => $query->where('school_class_id', $schoolClass->id)),
            ],
            'room_number' => ['nullable', 'string', 'max:20'],
            'class_teacher_id' => [
                'nullable', 'integer',
                Rule::exists('users', 'id')->where(function ($query) use ($schoolClass) {
                    $query->where('school_id', $schoolClass->school_id)
                        ->whereIn('role', [UserRole::Hod->value, UserRole::Teacher->value]);
                }),
            ],
        ];
    }
}
