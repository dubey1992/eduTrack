<?php

namespace App\Http\Requests\Attendance;

use App\Http\Requests\Concerns\ChecksSchoolDates;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class AttendanceRegisterRequest extends FormRequest
{
    use ChecksSchoolDates;

    /**
     * class_section_id arrives as a query param, not a route-bound model, so
     * there's nothing to check ownership of until after `rules()` confirms
     * it's a real id - a bad/missing id should fail validation (422), not
     * authorization (403). The controller does the actual
     * ClassSectionPolicy::viewAttendance check once the section is loaded.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'class_section_id' => ['required', 'integer', Rule::exists('class_sections', 'id')],
            'date' => ['required', 'date', $this->notInFuture()],
        ];
    }
}
