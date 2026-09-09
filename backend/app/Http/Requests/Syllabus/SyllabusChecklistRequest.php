<?php

namespace App\Http\Requests\Syllabus;

use Illuminate\Foundation\Http\FormRequest;

class SyllabusChecklistRequest extends FormRequest
{
    /**
     * class_section_id/subject_id arrive as query params, not route-bound
     * models, so there's nothing to check ownership of until after
     * `rules()` confirms they're real ids - a bad/missing id fails
     * validation (422), not authorization. The controller does the actual
     * SyllabusTopicPolicy::viewChecklist check once the section is loaded.
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
            'class_section_id' => ['required', 'integer', 'exists:class_sections,id'],
            'subject_id' => ['required', 'integer', 'exists:subjects,id'],
        ];
    }
}
