<?php

namespace App\Services;

use App\Models\Subject;
use App\Models\SyllabusTopic;
use Illuminate\Support\Collection;

class SyllabusTopicService
{
    /**
     * @return Collection<int, SyllabusTopic>
     */
    public function forSubject(Subject $subject): Collection
    {
        return SyllabusTopic::query()
            ->where('subject_id', $subject->id)
            ->orderBy('sequence_number')
            ->get();
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(Subject $subject, array $data): SyllabusTopic
    {
        return SyllabusTopic::create([
            'school_id' => $subject->school_id,
            'subject_id' => $subject->id,
            'title' => $data['title'],
            'sequence_number' => $data['sequence_number'],
        ]);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(SyllabusTopic $topic, array $data): SyllabusTopic
    {
        $topic->update($data);

        return $topic;
    }

    public function delete(SyllabusTopic $topic): void
    {
        $topic->delete();
    }
}
