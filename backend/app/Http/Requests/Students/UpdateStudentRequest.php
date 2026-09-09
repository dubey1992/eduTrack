<?php

namespace App\Http\Requests\Students;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateStudentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('student'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $student = $this->route('student');

        return [
            // school_id is fixed at creation, same as every other feature.
            'class_section_id' => [
                'sometimes', 'required', 'integer',
                Rule::exists('class_sections', 'id')->where(function ($query) use ($student) {
                    $query->whereIn('school_class_id', function ($query) use ($student) {
                        $query->select('id')->from('school_classes')->where('school_id', $student->school_id);
                    });
                }),
            ],
            'admission_number' => [
                'sometimes', 'required', 'string', 'max:30',
                Rule::unique('students', 'admission_number')
                    ->where(fn ($query) => $query->where('school_id', $student->school_id))
                    ->ignore($student->id),
            ],
            'first_name' => ['sometimes', 'required', 'string', 'max:100'],
            'last_name' => ['sometimes', 'required', 'string', 'max:100'],
            'roll_number' => ['nullable', 'string', 'max:20'],
            'guardian_name' => ['sometimes', 'required', 'string', 'max:150'],
            'guardian_mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'address' => ['nullable', 'string', 'max:500'],
        ];
    }
}
