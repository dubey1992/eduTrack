<?php

namespace App\Http\Requests\Syllabus;

use App\Models\SyllabusTopic;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class ToggleSyllabusProgressRequest extends FormRequest
{
    /**
     * Same split as the checklist request - a bad/missing id fails
     * validation (422), the SyllabusTopicPolicy::mark check runs in the
     * controller once both the topic and class section are loaded.
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
            'syllabus_topic_id' => ['required', 'integer', 'exists:syllabus_topics,id'],
            'class_section_id' => [
                'required', 'integer',
                Rule::exists('class_sections', 'id')->where(function ($query) {
                    $topic = SyllabusTopic::find($this->input('syllabus_topic_id'));
                    $query->whereIn('school_class_id', function ($query) use ($topic) {
                        $query->select('id')->from('school_classes')->where('school_id', $topic?->school_id);
                    });
                }),
            ],
            'completed' => ['required', 'boolean'],
        ];
    }
}
