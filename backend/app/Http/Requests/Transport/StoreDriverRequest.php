<?php

namespace App\Http\Requests\Transport;

use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\Driver;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreDriverRequest extends FormRequest
{
    use ScopesSchool;

    public function authorize(): bool
    {
        return $this->user()->can('create', Driver::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'school_id' => $this->schoolIdRules(),
            'name' => ['required', 'string', 'max:150'],
            'mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'licence_number' => [
                'required', 'string', 'max:50',
                Rule::unique('drivers', 'licence_number')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'licence_expiry' => ['nullable', 'date'],
        ];
    }
}
