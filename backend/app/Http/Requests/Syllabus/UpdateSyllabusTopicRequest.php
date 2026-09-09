<?php

namespace App\Http\Requests\Syllabus;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateSyllabusTopicRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('syllabusTopic'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $topic = $this->route('syllabusTopic');

        return [
            // subject_id is fixed at creation, same as every other phase's
            // parent-record fields - moving a topic to a different subject
            // is a new topic, not an edit.
            'title' => ['sometimes', 'required', 'string', 'max:255'],
            'sequence_number' => [
                'sometimes', 'required', 'integer', 'min:1',
                Rule::unique('syllabus_topics', 'sequence_number')
                    ->where(fn ($query) => $query->where('subject_id', $topic->subject_id))
                    ->ignore($topic->id),
            ],
        ];
    }
}
