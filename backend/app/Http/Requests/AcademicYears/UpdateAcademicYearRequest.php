<?php

namespace App\Http\Requests\AcademicYears;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

class UpdateAcademicYearRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('academicYear'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // school_id is fixed at creation, and is_current is only ever
            // changed via the dedicated set-current action - not here.
            'name' => ['sometimes', 'required', 'string', 'max:50'],
            'start_date' => ['sometimes', 'required', 'date'],
            'end_date' => ['sometimes', 'required', 'date'],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator) {
            $academicYear = $this->route('academicYear');
            $start = $this->input('start_date', $academicYear->start_date->toDateString());
            $end = $this->input('end_date', $academicYear->end_date->toDateString());

            if ($end <= $start) {
                $validator->errors()->add('end_date', 'The end date must be after the start date.');
            }
        });
    }
}
