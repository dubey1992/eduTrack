<?php

namespace App\Http\Requests\SchoolClasses;

use App\Enums\UserRole;
use App\Models\SchoolClass;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreSchoolClassRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', SchoolClass::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // The real client always sends this key - literal null for a
            // non-SuperAdmin, since school_id is taken from the actor's own
            // account server-side either way (see resolvedSchoolId()) -
            // so non-SuperAdmin gets its own minimal, null-tolerant rule set
            // rather than the full integer/exists check meant for SuperAdmin.
            'school_id' => $this->user()->role === UserRole::SuperAdmin
                ? ['required', 'integer', 'exists:schools,id']
                : ['nullable'],
            'academic_year_id' => [
                'required', 'integer',
                Rule::exists('academic_years', 'id')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'name' => [
                'required', 'string', 'max:50',
                Rule::unique('school_classes', 'name')->where(fn ($query) => $query->where('academic_year_id', $this->input('academic_year_id'))),
            ],
            'level' => ['required', 'integer', 'min:0', 'max:12'],
        ];
    }

    private function resolvedSchoolId(): ?int
    {
        return $this->user()->role === UserRole::SuperAdmin
            ? $this->integer('school_id')
            : $this->user()->school_id;
    }
}
