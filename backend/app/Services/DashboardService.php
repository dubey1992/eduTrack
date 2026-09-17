<?php

namespace App\Services;

use App\Enums\AttendanceStatus;
use App\Enums\LeaveStatus;
use App\Enums\MessageChannel;
use App\Enums\MessageStatus;
use App\Enums\PaymentStatus;
use App\Enums\SchoolStatus;
use App\Enums\StudentStatus;
use App\Enums\TransportStatus;
use App\Enums\TripStatus;
use App\Enums\UserRole;
use App\Enums\UserStatus;
use App\Models\Attendance;
use App\Models\ClassSection;
use App\Models\DailyTeachingReport;
use App\Models\Department;
use App\Models\Message;
use App\Models\Payment;
use App\Models\School;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\TimetableEntry;
use App\Models\TransportRoute;
use App\Models\TransportTrip;
use App\Models\User;
use App\Support\SchoolClock;
use App\Support\SchoolScope;
use Illuminate\Support\Carbon;

/**
 * The landing screen's figures, which differ by who is looking.
 *
 * Every role gets the same shape - a list of cards, plus an attendance trend
 * and a list of things wanting attention - so the client renders one layout
 * rather than six. What goes in them is decided per role here, where the
 * authorization rules already live, rather than by the client asking for
 * whatever it fancies.
 */
class DashboardService
{
    public function __construct(private readonly HolidayService $holidays) {}

    /**
     * @param  array<string, mixed>  $filters
     * @return array<string, mixed>
     */
    public function forUser(User $actor, array $filters): array
    {
        $schoolId = $this->schoolIdFor($actor, $filters);
        $clock = $schoolId === null ? SchoolClock::platform() : SchoolClock::for($schoolId);
        $today = $clock->date();

        $payload = match ($actor->role) {
            UserRole::SuperAdmin => $schoolId === null
                ? $this->platform($clock)
                : $this->school($schoolId, $today),
            // A branch they named, or the group as a whole. An admin of a
            // standalone school never reaches the group arm: their scope is
            // one school, so schoolIdFor() has already resolved it for them
            // and they land on their own figures as they always have.
            UserRole::GroupAdmin, UserRole::SchoolAdmin => $schoolId === null
                ? $this->group($actor, $today)
                : $this->school($schoolId, $today),
            UserRole::Hod => $this->hod($actor, $today),
            UserRole::Teacher => $this->teacher($actor, $today),
            UserRole::TransportManager => $this->transport((int) $actor->school_id, $today),
            UserRole::Staff => $this->staff($actor, $today),
        };

        return [
            'role' => $actor->role->value,
            'school_id' => $schoolId,
            'as_of' => $today,
            'is_working_day' => $schoolId !== null && $this->holidays->isWorkingDay($schoolId, $today),
            'holiday' => $schoolId === null ? null : $this->holidays->holidayOn($schoolId, $today)?->name,
            ...$payload,
        ];
    }

    // -- per role ---------------------------------------------------------

    /**
     * The Super Admin looking across every school. Money is grouped by
     * currency and never blended - CLAUDE.md rule 5.
     *
     * @return array<string, mixed>
     */
    private function platform(SchoolClock $clock): array
    {
        $collected = Payment::query()
            ->whereNot('status', PaymentStatus::Cancelled)
            ->selectRaw('currency_code, SUM(paid_amount) as total')
            ->groupBy('currency_code')
            ->havingRaw('SUM(paid_amount) > 0')
            // "INR 4,50,000.00 + USD 12,000.00" reads the same every time.
            ->orderBy('currency_code')
            ->get()
            ->map(fn ($row) => $row->currency_code.' '.number_format((float) $row->total, 2))
            ->implode(' + ');

        $outstanding = Payment::query()
            ->whereIn('status', [PaymentStatus::Pending, PaymentStatus::Partial])
            ->count();

        return [
            'cards' => [
                $this->card('schools', 'Schools', (string) School::count(), School::where('status', SchoolStatus::Active)->count().' active'),
                $this->card('users', 'User accounts', (string) User::where('status', UserStatus::Active)->count(), 'active'),
                $this->card('collected', 'Collected', $collected === '' ? '-' : $collected, 'money received'),
                $this->card('outstanding', 'Payments owing', (string) $outstanding, 'pending or part paid', $outstanding > 0 ? 'warning' : 'ok'),
            ],
            'attendance_trend' => [],
            'attention' => [],
        ];
    }

    /**
     * A whole school group at once - every branch beneath the parent.
     *
     * Roll-ups, not a blend: the attendance figure is the group's marked
     * students over its marked total, and each branch that has not marked
     * yet is named rather than quietly averaged away.
     *
     * @return array<string, mixed>
     */
    private function group(User $actor, string $today): array
    {
        $schoolIds = $actor->school?->groupSchoolIds() ?? [];
        $branches = School::query()->whereIn('id', $schoolIds)->orderBy('name')->orderBy('id')->get();

        $students = Student::whereIn('school_id', $schoolIds)->where('status', StudentStatus::Active)->count();
        $staff = StaffProfile::whereIn('school_id', $schoolIds)->count();
        $rate = $this->attendanceRateAcross($schoolIds, $today);

        $unmarked = $branches
            ->filter(fn (School $branch) => $this->attendanceRateOn($branch->id, $today) === null)
            ->map(fn (School $branch) => $this->note('attendance-'.$branch->id, "{$branch->name} has not marked attendance today."))
            ->values()
            ->all();

        return [
            'cards' => [
                $this->card('branches', 'Schools in group', (string) $branches->count(), 'including the parent'),
                $this->card('students', 'Students', (string) $students, 'across the group'),
                $this->card('staff', 'Teachers & staff', (string) $staff, 'across the group'),
                $this->card(
                    'attendance',
                    'Attendance today',
                    $rate === null ? '-' : $rate.'%',
                    $rate === null ? 'not marked yet' : 'of students present',
                ),
            ],
            'attendance_trend' => [],
            'attention' => $unmarked,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function school(int $schoolId, string $today): array
    {
        $students = Student::where('school_id', $schoolId)->where('status', StudentStatus::Active)->count();
        $staff = StaffProfile::where('school_id', $schoolId)->count();
        $rate = $this->attendanceRateOn($schoolId, $today);
        $tripsToday = TransportTrip::where('school_id', $schoolId)->where('trip_date', $today)->count();
        $routes = TransportRoute::where('school_id', $schoolId)->where('status', TransportStatus::Active)->count();

        return [
            'cards' => [
                $this->card('students', 'Students', (string) $students, 'on the roll'),
                $this->card('staff', 'Teachers & staff', (string) $staff, 'on the payroll'),
                $this->card('attendance', 'Attendance today', $rate === null ? '-' : $rate.'%', $rate === null ? 'not marked yet' : 'of students present'),
                $this->card('transport', 'Trips today', (string) $tripsToday, $routes.' active routes'),
            ],
            'attendance_trend' => $this->attendanceTrend($schoolId, $today),
            'attention' => $this->schoolAttention($schoolId, $today),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function hod(User $actor, string $today): array
    {
        $schoolId = (int) $actor->school_id;
        $departmentIds = Department::where('school_id', $schoolId)
            ->where('hod_user_id', $actor->id)
            ->pluck('id');

        $teachers = StaffProfile::where('school_id', $schoolId)
            ->whereIn('department_id', $departmentIds)
            ->count();

        $pendingReviews = DailyTeachingReport::where('school_id', $schoolId)
            ->whereNull('reviewed_at')
            ->whereHas('timetableEntry.subject', fn ($query) => $query->whereIn('department_id', $departmentIds))
            ->count();

        return [
            'cards' => [
                $this->card('departments', 'Departments', (string) $departmentIds->count(), 'you head'),
                $this->card('teachers', 'Teachers', (string) $teachers, 'in your departments'),
                $this->card('reviews', 'Reports to review', (string) $pendingReviews, 'awaiting you', $pendingReviews > 0 ? 'warning' : 'ok'),
            ],
            'attendance_trend' => $this->attendanceTrend($schoolId, $today),
            'attention' => $pendingReviews === 0 ? [] : [
                $this->note('reviews', "{$pendingReviews} teaching reports are waiting for your review."),
            ],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function teacher(User $actor, string $today): array
    {
        $schoolId = (int) $actor->school_id;
        $weekday = strtolower(Carbon::parse($today)->format('l'));

        $periodsToday = TimetableEntry::where('school_id', $schoolId)
            ->where('teacher_id', $actor->id)
            ->where('day_of_week', $weekday)
            ->count();

        $reportsFiled = DailyTeachingReport::where('school_id', $schoolId)
            ->where('teacher_id', $actor->id)
            ->where('report_date', $today)
            ->count();

        $sectionsToMark = $this->sectionsAwaitingRegister($actor, $today);

        return [
            'cards' => [
                $this->card('periods', 'Periods today', (string) $periodsToday, 'on your timetable'),
                $this->card('reports', 'Reports filed', "{$reportsFiled}/{$periodsToday}", 'for today', $reportsFiled < $periodsToday ? 'warning' : 'ok'),
                $this->card('register', 'Registers to mark', (string) $sectionsToMark, 'your class sections', $sectionsToMark > 0 ? 'warning' : 'ok'),
            ],
            'attendance_trend' => [],
            'attention' => $sectionsToMark === 0 ? [] : [
                $this->note('register', 'Today\'s register has not been marked for your class yet.'),
            ],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function transport(int $schoolId, string $today): array
    {
        $trips = TransportTrip::where('school_id', $schoolId)->where('trip_date', $today)->get();
        $routes = TransportRoute::where('school_id', $schoolId)->where('status', TransportStatus::Active)->count();
        $running = $trips->where('status', TripStatus::InProgress)->count();

        return [
            'cards' => [
                $this->card('routes', 'Active routes', (string) $routes, 'in service'),
                $this->card('running', 'Trips running', (string) $running, 'right now'),
                $this->card('completed', 'Trips completed', (string) $trips->where('status', TripStatus::Completed)->count(), 'today'),
            ],
            'attendance_trend' => [],
            'attention' => [],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function staff(User $actor, string $today): array
    {
        $schoolId = (int) $actor->school_id;
        $profile = StaffProfile::where('user_id', $actor->id)->first();

        $pendingLeave = $profile === null ? 0 : StaffLeave::where('staff_profile_id', $profile->id)
            ->where('status', LeaveStatus::Pending)
            ->count();

        $unread = Message::where('user_id', $actor->id)
            ->where('channel', MessageChannel::InApp)
            ->whereNull('read_at')
            ->count();

        return [
            'cards' => [
                $this->card('leave', 'Leave requests', (string) $pendingLeave, 'awaiting a decision'),
                $this->card('inbox', 'Unread messages', (string) $unread, 'in your inbox', $unread > 0 ? 'warning' : 'ok'),
            ],
            'attendance_trend' => [],
            'attention' => [],
        ];
    }

    // -- shared pieces ----------------------------------------------------

    /**
     * The percentage of students present on one day, or null when nobody has
     * marked a register yet. Null rather than zero: "not marked" and
     * "everybody absent" are very different things to show a head teacher.
     */
    /**
     * The same figure as attendanceRateOn(), over several schools at once.
     *
     * One ratio across the group, not an average of averages - a branch of
     * forty and a branch of four hundred should not weigh the same.
     *
     * @param  array<int, int>  $schoolIds
     */
    private function attendanceRateAcross(array $schoolIds, string $date): ?float
    {
        $marks = Attendance::whereIn('school_id', $schoolIds)
            ->where('attendance_date', $date)
            ->selectRaw('status as status_value, COUNT(*) as total')
            ->groupBy('status')
            ->pluck('total', 'status_value');

        $total = (int) $marks->sum();

        if ($total === 0) {
            return null;
        }

        return round(((int) $marks->get(AttendanceStatus::Present->value, 0)) / $total * 100, 1);
    }

    private function attendanceRateOn(int $schoolId, string $date): ?float
    {
        $marks = Attendance::where('school_id', $schoolId)
            ->where('attendance_date', $date)
            ->selectRaw('status as status_value, COUNT(*) as total')
            ->groupBy('status')
            ->pluck('total', 'status_value');

        $total = (int) $marks->sum();

        if ($total === 0) {
            return null;
        }

        return round(((int) $marks->get(AttendanceStatus::Present->value, 0)) / $total * 100, 1);
    }

    /**
     * The last working days, oldest first, for the trend line.
     *
     * Working days rather than calendar days, so a chart never shows a
     * weekend or a holiday sitting at zero as though a school had emptied.
     *
     * @return array<int, array<string, mixed>>
     */
    private function attendanceTrend(int $schoolId, string $today, int $days = 7): array
    {
        $dates = $this->holidays
            ->workingDates($schoolId, Carbon::parse($today)->subDays($days * 3), Carbon::parse($today))
            ->take(-$days);

        return $dates->map(fn (string $date) => [
            'date' => $date,
            'label' => Carbon::parse($date)->format('d M'),
            'attendance_rate' => $this->attendanceRateOn($schoolId, $date),
        ])->values()->all();
    }

    /**
     * @return array<int, array<string, string>>
     */
    private function schoolAttention(int $schoolId, string $today): array
    {
        $notes = [];

        if ($this->holidays->isWorkingDay($schoolId, $today) && $this->attendanceRateOn($schoolId, $today) === null) {
            $notes[] = $this->note('attendance', 'No attendance has been marked yet today.');
        }

        $failed = Message::where('school_id', $schoolId)->where('status', MessageStatus::Failed)->count();
        if ($failed > 0) {
            $notes[] = $this->note('messages', "{$failed} messages failed to send and can be retried.");
        }

        $pendingLeave = StaffLeave::where('school_id', $schoolId)
            ->where('status', LeaveStatus::Pending)
            ->count();
        if ($pendingLeave > 0) {
            $notes[] = $this->note('leave', "{$pendingLeave} leave requests are waiting for a decision.");
        }

        return $notes;
    }

    /**
     * Class sections this teacher is responsible for that have no register
     * for the day yet.
     */
    private function sectionsAwaitingRegister(User $actor, string $today): int
    {
        if (! $this->holidays->isWorkingDay((int) $actor->school_id, $today)) {
            return 0;
        }

        return ClassSection::query()
            ->where('class_teacher_id', $actor->id)
            ->whereDoesntHave('attendances', fn ($query) => $query->where('attendance_date', $today))
            ->count();
    }

    /**
     * @return array<string, string|null>
     */
    private function card(string $key, string $label, string $value, ?string $hint = null, string $tone = 'neutral'): array
    {
        return ['key' => $key, 'label' => $label, 'value' => $value, 'hint' => $hint, 'tone' => $tone];
    }

    /**
     * @return array<string, string>
     */
    private function note(string $key, string $message): array
    {
        return ['key' => $key, 'message' => $message];
    }

    /**
     * @param  array<string, mixed>  $filters
     */
    private function schoolIdFor(User $actor, array $filters): ?int
    {
        return SchoolScope::for($actor)->writableSchoolId(
            isset($filters['school_id']) ? (int) $filters['school_id'] : null
        );
    }
}
