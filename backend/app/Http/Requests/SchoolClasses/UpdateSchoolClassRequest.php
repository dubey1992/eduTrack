<?php

namespace App\Http\Requests\SchoolClasses;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateSchoolClassRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('schoolClass'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $schoolClass = $this->route('schoolClass');

        return [
            // school_id and academic_year_id are fixed at creation - moving
            // a class to a different year is a new class, not an edit.
            'name' => [
                'sometimes', 'required', 'string', 'max:50',
                Rule::unique('school_classes', 'name')
                    ->where(fn ($query) => $query->where('academic_year_id', $schoolClass->academic_year_id))
                    ->ignore($schoolClass->id),
            ],
            'level' => ['sometimes', 'required', 'integer', 'min:0', 'max:12'],
        ];
    }
}
