<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Exceptions\TeachingReportAlreadyReviewedException;
use App\Exceptions\TeachingReportAlreadySubmittedException;
use App\Models\DailyTeachingReport;
use App\Models\TimetableEntry;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Carbon;

class DailyTeachingReportService
{
    private const array RELATIONS = [
        'timetableEntry.classSection.schoolClass', 'timetableEntry.period', 'timetableEntry.subject', 'teacher', 'reviewedBy',
    ];

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(TimetableEntry $entry, array $data, User $actor): DailyTeachingReport
    {
        $this->assertNoDuplicate($entry->id, $data['report_date']);

        $report = DailyTeachingReport::create([
            'school_id' => $entry->school_id,
            'timetable_entry_id' => $entry->id,
            'teacher_id' => $actor->id,
            'report_date' => $data['report_date'],
            'topic_taught' => $data['topic_taught'],
            'homework' => $data['homework'] ?? null,
            'remarks' => $data['remarks'] ?? null,
        ]);

        return $report->load(self::RELATIONS);
    }

    public function review(DailyTeachingReport $report, User $actor): DailyTeachingReport
    {
        if ($report->reviewed_by !== null) {
            throw new TeachingReportAlreadyReviewedException('This report has already been reviewed.');
        }

        $report->update(['reviewed_by' => $actor->id, 'reviewed_at' => now()]);

        return $report->fresh(self::RELATIONS);
    }

    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return $this->scopedQuery($actor, $filters['school_id'] ?? null)
            ->with(self::RELATIONS)
            ->when($filters['teacher_id'] ?? null, fn ($query, $teacherId) => $query->where('teacher_id', $teacherId))
            ->when($filters['report_date'] ?? null, fn ($query, $date) => $query->where('report_date', $date))
            ->orderByDesc('report_date')
            ->orderBy('teacher_id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * The KPI row the prototype's Daily Teaching Report screen shows -
     * Scheduled comes straight from Phase 10's timetable_entries (every
     * entry whose day_of_week matches the given date), Submitted from this
     * table, both counted over the same role-scoped visibility as
     * paginate(). "Conducted" isn't included - this system has no signal
     * for it independent of "a report was filed".
     *
     * @param  array<string, mixed>  $filters
     * @return array<string, int>
     */
    public function summary(User $actor, array $filters, string $date): array
    {
        $dayOfWeek = strtolower(Carbon::parse($date)->format('l'));

        $scheduled = $this->scopedTimetableQuery($actor, $filters['school_id'] ?? null)
            ->where('day_of_week', $dayOfWeek)
            ->count();

        $submitted = $this->scopedQuery($actor, $filters['school_id'] ?? null)
            ->where('report_date', $date)
            ->count();

        return [
            'scheduled' => $scheduled,
            'submitted' => $submitted,
            'pending' => max(0, $scheduled - $submitted),
        ];
    }

    private function assertNoDuplicate(int $timetableEntryId, string $reportDate): void
    {
        $exists = DailyTeachingReport::query()
            ->where('timetable_entry_id', $timetableEntryId)
            ->where('report_date', $reportDate)
            ->exists();

        if ($exists) {
            throw new TeachingReportAlreadySubmittedException('A report has already been submitted for this period and date.');
        }
    }

    /**
     * @return Builder<DailyTeachingReport>
     */
    private function scopedQuery(User $actor, ?int $schoolIdFilter): Builder
    {
        return DailyTeachingReport::query()
            ->when(
                $actor->role === UserRole::SuperAdmin,
                fn ($query) => $query->when($schoolIdFilter, fn ($query, $id) => $query->where('school_id', $id)),
                fn ($query) => $query->where('school_id', $actor->school_id)
            )
            // An HOD only ever sees reports filed by teachers in the
            // department(s) they head - same rule as StaffLeaveService.
            ->when(
                $actor->role === UserRole::Hod,
                fn ($query) => $query->whereHas(
                    'teacher.staffProfile.department',
                    fn ($query) => $query->where('hod_user_id', $actor->id)
                )
            )
            // A Teacher only ever sees their own reports - they aren't
            // reviewers, this is self-service.
            ->when(
                $actor->role === UserRole::Teacher,
                fn ($query) => $query->where('teacher_id', $actor->id)
            );
    }

    /**
     * @return Builder<TimetableEntry>
     */
    private function scopedTimetableQuery(User $actor, ?int $schoolIdFilter): Builder
    {
        return TimetableEntry::query()
            ->when(
                $actor->role === UserRole::SuperAdmin,
                fn ($query) => $query->when($schoolIdFilter, fn ($query, $id) => $query->where('school_id', $id)),
                fn ($query) => $query->where('school_id', $actor->school_id)
            )
            ->when(
                $actor->role === UserRole::Hod,
                fn ($query) => $query->whereHas(
                    'teacher.staffProfile.department',
                    fn ($query) => $query->where('hod_user_id', $actor->id)
                )
            )
            ->when(
                $actor->role === UserRole::Teacher,
                fn ($query) => $query->where('teacher_id', $actor->id)
            );
    }
}
