<?php

namespace App\Http\Requests\AcademicYears;

use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\AcademicYear;
use Illuminate\Foundation\Http\FormRequest;

class StoreAcademicYearRequest extends FormRequest
{
    use ScopesSchool;

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
            // An actor pinned to one school never picks one - the service
            // forces their own school_id regardless of what is sent.
            'school_id' => $this->schoolIdRules(),
            'name' => ['required', 'string', 'max:50'],
            'start_date' => ['required', 'date'],
            'end_date' => ['required', 'date', 'after:start_date'],
            'is_current' => ['sometimes', 'boolean'],
        ];
    }
}
