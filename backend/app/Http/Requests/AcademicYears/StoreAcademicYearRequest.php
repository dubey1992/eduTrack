<?php

namespace App\Http\Requests\AcademicYears;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreAcademicYearRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', AcademicYear::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // SCHOOL_ADMIN never picks a school - the service forces their
            // own school_id regardless of what's sent.
            'school_id' => [
                Rule::requiredIf(fn () => $this->user()->role === UserRole::SuperAdmin),
                'integer', 'exists:schools,id',
            ],
            'name' => ['required', 'string', 'max:50'],
            'start_date' => ['required', 'date'],
            'end_date' => ['required', 'date', 'after:start_date'],
            'is_current' => ['sometimes', 'boolean'],
        ];
    }
}
