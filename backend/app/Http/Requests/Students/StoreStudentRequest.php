<?php

namespace App\Http\Requests\Students;

use App\Enums\UserRole;
use App\Models\Student;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreStudentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Student::class);
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
            'class_section_id' => [
                'required', 'integer',
                // class_sections has no school_id column of its own - reach
                // it through school_classes.
                Rule::exists('class_sections', 'id')->where(function ($query) {
                    $query->whereIn('school_class_id', function ($query) {
                        $query->select('id')->from('school_classes')->where('school_id', $this->resolvedSchoolId());
                    });
                }),
            ],
            'admission_number' => [
                'required', 'string', 'max:30',
                Rule::unique('students', 'admission_number')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'first_name' => ['required', 'string', 'max:100'],
            'last_name' => ['required', 'string', 'max:100'],
            'roll_number' => ['nullable', 'string', 'max:20'],
            'guardian_name' => ['required', 'string', 'max:150'],
            'guardian_mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'address' => ['nullable', 'string', 'max:500'],
        ];
    }

    private function resolvedSchoolId(): ?int
    {
        return $this->user()->role === UserRole::SuperAdmin
            ? $this->integer('school_id')
            : $this->user()->school_id;
    }
}
