<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Http\Requests\Reports\ReportRequest;
use App\Models\Department;
use App\Models\User;
use App\Services\HolidayService;
use App\Services\Reports\StaffAttendanceReport;
use App\Services\Reports\StudentAttendanceReport;
use App\Services\Reports\TeachingCoverageReport;
use App\Services\Reports\TransportUsageReport;
use App\Support\Reports\CsvResponse;
use App\Support\Reports\ReportRange;
use App\Support\SchoolScope;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Http\JsonResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * The four reports, each available as JSON for the screen or CSV for a
 * spreadsheet - the same figures either way, built by the same service.
 *
 * Who may see what is decided here rather than in a policy, because these are
 * not records with owners: each report has its own audience, and saying so in
 * one place beats four near-identical policy classes.
 */
class ReportController extends Controller
{
    public function __construct(private readonly HolidayService $holidays) {}

    public function studentAttendance(ReportRequest $request, StudentAttendanceReport $report): JsonResponse|StreamedResponse
    {
        $this->allow($request->user(), [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin]);

        return $this->respond($request, $report, 'student-attendance');
    }

    public function staffAttendance(ReportRequest $request, StaffAttendanceReport $report): JsonResponse|StreamedResponse
    {
        $this->allow($request->user(), [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin, UserRole::Hod]);

        return $this->respond($request, $report, 'staff-attendance');
    }

    public function teachingCoverage(ReportRequest $request, TeachingCoverageReport $report): JsonResponse|StreamedResponse
    {
        $this->allow($request->user(), [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin, UserRole::Hod]);

        return $this->respond($request, $report, 'teaching-coverage');
    }

    public function transportUsage(ReportRequest $request, TransportUsageReport $report): JsonResponse|StreamedResponse
    {
        $this->allow($request->user(), [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin, UserRole::TransportManager]);

        return $this->respond($request, $report, 'transport-usage');
    }

    /**
     * @param  StudentAttendanceReport|StaffAttendanceReport|TeachingCoverageReport|TransportUsageReport  $report
     */
    private function respond(ReportRequest $request, object $report, string $name): JsonResponse|StreamedResponse
    {
        $actor = $request->user();
        $schoolId = $this->schoolIdFor($actor, $request);
        $filters = $this->filtersFor($actor, $request);

        $range = ReportRange::fromFilters($schoolId, $filters, $this->holidays);
        $built = $report->build($range, $filters);

        if (! $request->wantsCsv()) {
            return response()->json($built);
        }

        [$from, $to] = $range->bounds();

        return CsvResponse::make(
            "{$name}-{$from}-to-{$to}.csv",
            $report->headings(),
            $report->csvRows($built),
        );
    }

    /**
     * A school user's report is always their own school's. Only a Super
     * Admin, who belongs to none, names the school they want.
     */
    private function schoolIdFor(User $actor, ReportRequest $request): int
    {
        return (int) SchoolScope::for($actor)->writableSchoolId($request->integer('school_id') ?: null);
    }

    /**
     * @return array<string, mixed>
     */
    private function filtersFor(User $actor, ReportRequest $request): array
    {
        $filters = $request->only(['from', 'to', 'class_section_id', 'department_id']);

        // A head of department reports on their own departments, whatever
        // they ask for - the scope is theirs, not the request's.
        if ($actor->role === UserRole::Hod) {
            $filters['department_ids'] = Department::query()
                ->where('school_id', $actor->school_id)
                ->where('hod_user_id', $actor->id)
                ->pluck('id')
                ->all();
        }

        return $filters;
    }

    /**
     * @param  array<int, UserRole>  $roles
     *
     * @throws AuthorizationException
     */
    private function allow(User $actor, array $roles): void
    {
        if (! in_array($actor->role, $roles, true)) {
            throw new AuthorizationException('You do not have access to this report.');
        }
    }
}
