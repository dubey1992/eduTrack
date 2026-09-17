<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Http\Requests\Reports\ReportRequest;
use App\Models\Department;
use App\Models\School;
use App\Models\User;
use App\Services\HolidayService;
use App\Services\Reports\StaffAttendanceReport;
use App\Services\Reports\StudentAttendanceReport;
use App\Services\Reports\TeachingCoverageReport;
use App\Services\Reports\TransportUsageReport;
use App\Support\Reports\CsvResponse;
use App\Support\Reports\GroupReport;
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
        $filters = $this->filtersFor($actor, $request);
        $scope = SchoolScope::for($actor);
        // A branch outside the actor's reach is ignored rather than refused,
        // the same as every other school filter in the app.
        $requested = $request->integer('school_id') ?: null;
        $requested = $scope->allows($requested) ? $requested : null;

        // A Group Admin who names no reachable branch means the whole group.
        // Everybody else is reporting on exactly one school, whether they
        // named it or it was decided for them.
        $built = $requested === null && $scope->coversAGroup()
            ? $this->group($scope, $report, $filters)
            : $this->single((int) $scope->writableSchoolId($requested), $report, $filters);

        if (! $request->wantsCsv()) {
            return response()->json($built);
        }

        $isGroup = $built['group'] ?? false;
        $from = $built['range']['from'];
        $to = $built['range']['to'];

        return CsvResponse::make(
            $isGroup ? "{$name}-group-{$from}-to-{$to}.csv" : "{$name}-{$from}-to-{$to}.csv",
            // A group export has to say which branch a line came from, or the
            // rows are a heap.
            $isGroup ? ['School', ...$report->headings()] : $report->headings(),
            $isGroup
                ? array_map(
                    fn (array $row, array $csv) => [$row['school_name'], ...$csv],
                    $built['rows'],
                    $report->csvRows($built),
                )
                : $report->csvRows($built),
        );
    }

    /**
     * @param  StudentAttendanceReport|StaffAttendanceReport|TeachingCoverageReport|TransportUsageReport  $report
     * @param  array<string, mixed>  $filters
     * @return array<string, mixed>
     */
    private function single(int $schoolId, object $report, array $filters): array
    {
        return $report->build(ReportRange::fromFilters($schoolId, $filters, $this->holidays), $filters);
    }

    /**
     * The same report across every branch, run once per branch because each
     * has its own holiday calendar. See App\Support\Reports\GroupReport.
     *
     * @param  StudentAttendanceReport|StaffAttendanceReport|TeachingCoverageReport|TransportUsageReport  $report
     * @param  array<string, mixed>  $filters
     * @return array<string, mixed>
     */
    private function group(SchoolScope $scope, object $report, array $filters): array
    {
        $schools = School::query()->whereIn('id', $scope->ids() ?? [])->orderBy('name')->orderBy('id')->get();

        return GroupReport::build(
            $schools,
            fn (School $school) => $this->single($school->id, $report, $filters),
            $report,
        );
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
