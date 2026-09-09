<?php

namespace App\Services;

use App\Models\ClassSection;
use App\Models\Subject;
use App\Models\SyllabusTopic;
use App\Models\SyllabusTopicProgress;
use App\Models\User;

class SyllabusProgressService
{
    /**
     * A subject's ordered topics, each paired with this class section's
     * completion mark (or null if not yet covered) - the syllabus
     * equivalent of AttendanceService::register().
     *
     * @return array<string, mixed>
     */
    public function checklist(Subject $subject, ClassSection $section): array
    {
        $topics = SyllabusTopic::query()
            ->where('subject_id', $subject->id)
            ->orderBy('sequence_number')
            ->get();

        $progress = SyllabusTopicProgress::query()
            ->where('class_section_id', $section->id)
            ->whereIn('syllabus_topic_id', $topics->pluck('id'))
            ->with('completedBy')
            ->get()
            ->keyBy('syllabus_topic_id');

        $completedCount = $progress->count();
        $totalCount = $topics->count();

        return [
            'subject_id' => $subject->id,
            'subject_name' => $subject->name,
            'class_section_id' => $section->id,
            'total_topics' => $totalCount,
            'completed_topics' => $completedCount,
            'progress_percent' => $totalCount === 0 ? 0 : (int) round($completedCount / $totalCount * 100),
            'topics' => $topics->map(function (SyllabusTopic $topic) use ($progress) {
                $mark = $progress->get($topic->id);

                return [
                    'id' => $topic->id,
                    'title' => $topic->title,
                    'sequence_number' => $topic->sequence_number,
                    'completed' => $mark !== null,
                    'completed_by_name' => $mark?->completedBy?->name,
                    'completed_at' => $mark?->completed_at,
                ];
            })->values()->all(),
        ];
    }

    public function toggle(SyllabusTopic $topic, ClassSection $section, bool $completed, User $actor): void
    {
        if ($completed) {
            SyllabusTopicProgress::updateOrCreate(
                ['syllabus_topic_id' => $topic->id, 'class_section_id' => $section->id],
                ['school_id' => $topic->school_id, 'completed_by' => $actor->id, 'completed_at' => now()]
            );

            return;
        }

        SyllabusTopicProgress::query()
            ->where('syllabus_topic_id', $topic->id)
            ->where('class_section_id', $section->id)
            ->delete();
    }
}
