<?php

namespace App\Services;

use App\Enums\AttendanceStatus;
use App\Enums\MessageEvent;
use App\Enums\StudentStatus;
use App\Enums\UserRole;
use App\Exceptions\AttendanceAlreadySubmittedException;
use App\Exceptions\AttendanceOnHolidayException;
use App\Exceptions\NonWorkingDayException;
use App\Models\Attendance;
use App\Models\ClassSection;
use App\Models\Holiday;
use App\Models\Student;
use App\Models\User;
use App\Support\DateFormats;
use App\Support\SchoolScope;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

class AttendanceService
{
    public function __construct(
        private readonly HolidayService $holidayService,
        private readonly NotificationService $notifications,
    ) {}

    /**
     * The class's active roster for one day, each student paired with their
     * existing mark (or null if the day hasn't been submitted yet). If the
     * day is on the school's holiday calendar, `holiday` says which one -
     * the client shows it and submit()/update() refuse to mark.
     *
     * @return array<string, mixed>
     */
    public function register(ClassSection $section, string $date): array
    {
        $students = $section->students()
            ->where('status', StudentStatus::Active)
            ->orderBy('first_name')
            ->get();

        $existing = Attendance::query()
            ->where('class_section_id', $section->id)
            ->where('attendance_date', $date)
            ->get()
            ->keyBy('student_id');

        $holiday = $this->holidayService->holidayOn($section->schoolClass->school_id, $date);

        return [
            'class_section_id' => $section->id,
            'attendance_date' => $date,
            'submitted' => $existing->isNotEmpty(),
            'holiday' => $holiday === null ? null : self::holidayPayload($holiday),
            'students' => $students->map(fn (Student $student) => [
                'student_id' => $student->id,
                'name' => $student->name,
                'roll_number' => $student->roll_number,
                'status' => $existing->get($student->id)?->status->value,
                'remarks' => $existing->get($student->id)?->remarks,
            ])->values()->all(),
        ];
    }

    /**
     * First submission for a class+day - rejected if one already exists, so
     * a duplicate tap can't silently overwrite a different set of marks.
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    public function submit(ClassSection $section, array $data, User $actor): array
    {
        $alreadySubmitted = Attendance::query()
            ->where('class_section_id', $section->id)
            ->where('attendance_date', $data['attendance_date'])
            ->exists();

        if ($alreadySubmitted) {
            throw new AttendanceAlreadySubmittedException('Attendance has already been submitted.');
        }

        return $this->save($section, $data, $actor);
    }

    /**
     * A register can only be taken for a day the school actually ran.
     *
     * Both halves matter: a holiday names itself, and a weekend is refused
     * too, because every working-day figure in the product excludes both. A
     * Saturday register that no percentage counts is worse than none.
     */
    private function assertSchoolIsOpen(int $schoolId, string $date): void
    {
        $holiday = $this->holidayService->holidayOn($schoolId, $date);

        if ($holiday !== null) {
            throw new AttendanceOnHolidayException("Attendance cannot be marked on {$holiday->name} - it is a holiday.");
        }

        if (! $this->holidayService->isWorkingDay($schoolId, $date)) {
            throw new NonWorkingDayException('Attendance cannot be marked on a weekend - the school is closed.');
        }
    }

    /**
     * Corrects an already-submitted day (or fills in a student the first
     * submission missed) - an explicit, separate action from submit().
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    public function update(ClassSection $section, array $data, User $actor): array
    {
        return $this->save($section, $data, $actor);
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    private function save(ClassSection $section, array $data, User $actor): array
    {
        // Never trusted from the client - derived the same way
        // School/currency snapshots are (CLAUDE.md rule 5's pattern).
        $schoolId = $section->schoolClass->school_id;
        $academicYearId = $section->schoolClass->academic_year_id;

        $this->assertSchoolIsOpen($schoolId, $data['attendance_date']);

        return DB::transaction(function () use ($section, $data, $actor, $schoolId, $academicYearId) {
            $changed = [];

            foreach ($data['records'] as $record) {
                $attendance = Attendance::updateOrCreate(
                    [
                        'class_section_id' => $section->id,
                        'student_id' => $record['student_id'],
                        'attendance_date' => $data['attendance_date'],
                    ],
                    [
                        'school_id' => $schoolId,
                        'academic_year_id' => $academicYearId,
                        'status' => $record['status'],
                        'remarks' => $record['remarks'] ?? null,
                        'marked_by' => $actor->id,
                    ]
                );

                // Only a new mark or a changed one alerts the guardian, so
                // correcting a remark does not text a parent twice.
                if ($attendance->wasRecentlyCreated || $attendance->wasChanged('status')) {
                    $changed[$attendance->student_id] = $attendance->status;
                }
            }

            $this->alertGuardians($section, $data['attendance_date'], $changed, $actor);

            return $this->register($section, $data['attendance_date']);
        });
    }

    /**
     * Tells guardians what was marked. Which statuses actually go out is the
     * school's choice (Communication settings), and the send itself is queued
     * after this transaction commits - marking attendance is never held up by
     * a gateway.
     *
     * @param  array<int, AttendanceStatus>  $changed
     */
    private function alertGuardians(ClassSection $section, string $date, array $changed, User $actor): void
    {
        if ($changed === []) {
            return;
        }

        $students = Student::query()
            ->with('school')
            ->whereIn('id', array_keys($changed))
            ->get();

        foreach ($students as $student) {
            $event = match ($changed[$student->id]) {
                AttendanceStatus::Absent => MessageEvent::AttendanceAbsent,
                AttendanceStatus::Present => MessageEvent::AttendancePresent,
                default => null,
            };

            if ($event === null) {
                continue;
            }

            $this->notifications->notifyGuardian($event, $student, [
                'class_name' => trim("{$section->schoolClass->name} {$section->name}"),
                'date' => Carbon::parse($date)->format(DateFormats::DATE),
            ], $actor);
        }
    }

    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return Attendance::query()
            ->with(['student', 'classSection.schoolClass', 'markedBy'])
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $filters['school_id'] ?? null))
            // A teacher only ever sees attendance for sections they are the
            // class teacher of - never another class, regardless of filters.
            ->when(
                $actor->role === UserRole::Teacher,
                fn ($query) => $query->whereHas(
                    'classSection',
                    fn ($query) => $query->where('class_teacher_id', $actor->id)
                )
            )
            ->when(
                $filters['class_section_id'] ?? null,
                fn ($query, $classSectionId) => $query->where('class_section_id', $classSectionId)
            )
            ->when($filters['student_id'] ?? null, fn ($query, $studentId) => $query->where('student_id', $studentId))
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            ->when(
                $filters['date_from'] ?? null,
                fn ($query, $date) => $query->where('attendance_date', '>=', $date)
            )
            ->when(
                $filters['date_to'] ?? null,
                fn ($query, $date) => $query->where('attendance_date', '<=', $date)
            )
            ->orderByDesc('attendance_date')
            ->orderBy('student_id')
            ->paginate(perPage: 20);
    }

    /**
     * The holiday summary both registers (student and staff) return.
     *
     * @return array{id: int, name: string, type: string}
     */
    public static function holidayPayload(Holiday $holiday): array
    {
        return ['id' => $holiday->id, 'name' => $holiday->name, 'type' => $holiday->type->value];
    }
}
