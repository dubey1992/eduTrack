<?php

namespace App\Http\Requests\Timetable;

use Illuminate\Foundation\Http\FormRequest;

/**
 * The grid is sliced one of two ways: by class section (the prototype's
 * "Timetable & Period Management" screen - one class's whole week) or by
 * teacher ("my timetable" - one teacher's periods across every class
 * section they teach). Exactly one of the two is required.
 */
class TimetableGridRequest extends FormRequest
{
    /**
     * school_id/class_section_id/teacher_id are query params here, not
     * route-bound models - a bad id fails validation (422), ownership is
     * checked once the target is loaded (see TimetableController).
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
            'class_section_id' => ['required_without:teacher_id', 'prohibits:teacher_id', 'integer', 'exists:class_sections,id'],
            'teacher_id' => ['required_without:class_section_id', 'integer', 'exists:users,id'],
        ];
    }
}
