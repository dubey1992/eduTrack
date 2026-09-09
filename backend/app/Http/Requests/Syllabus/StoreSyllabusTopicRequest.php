<?php

namespace App\Http\Requests\Syllabus;

use App\Enums\UserRole;
use App\Models\Subject;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreSyllabusTopicRequest extends FormRequest
{
    /**
     * The role gate (SyllabusTopicPolicy::create) needs the subject loaded
     * first, so it's checked in the controller once `subject_id` has passed
     * validation here - a missing/invalid field fails validation (422), not
     * authorization, same split as every other phase's create request.
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
            // The real client always sends this key - literal null for a
            // non-SuperAdmin, since school_id is taken from the actor's own
            // account server-side either way (see resolvedSchoolId()).
            'school_id' => $this->user()->role === UserRole::SuperAdmin
                ? ['required', 'integer', 'exists:schools,id']
                : ['nullable'],
            'subject_id' => [
                'required', 'integer',
                Rule::exists('subjects', 'id')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'title' => ['required', 'string', 'max:255'],
            'sequence_number' => [
                'required', 'integer', 'min:1',
                Rule::unique('syllabus_topics', 'sequence_number')
                    ->where(fn ($query) => $query->where('subject_id', $this->input('subject_id'))),
            ],
        ];
    }

    public function subject(): Subject
    {
        return Subject::findOrFail($this->validated('subject_id'));
    }

    private function resolvedSchoolId(): ?int
    {
        return $this->user()->role === UserRole::SuperAdmin
            ? $this->integer('school_id')
            : $this->user()->school_id;
    }
}
