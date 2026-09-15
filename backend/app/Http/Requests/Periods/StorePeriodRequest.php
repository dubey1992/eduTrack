<?php

namespace App\Http\Requests\Periods;

use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\Period;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StorePeriodRequest extends FormRequest
{
    use ScopesSchool;

    public function authorize(): bool
    {
        return $this->user()->can('create', Period::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // The real client always sends this key - literal null for a
            // non-SuperAdmin, since school_id is taken from the actor's own
            // account server-side either way. See resolvedSchoolId().
            'school_id' => $this->schoolIdRules(),
            'period_number' => [
                'required', 'integer', 'min:1', 'max:20',
                Rule::unique('periods', 'period_number')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'start_time' => ['required', 'date_format:H:i'],
            'end_time' => ['required', 'date_format:H:i', 'after:start_time'],
        ];
    }
}
