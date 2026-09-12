<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Http\Requests\Hod\HodDepartmentReportRequest;
use App\Models\Department;
use App\Models\School;
use App\Services\HodReportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Gate;

class HodReportController extends Controller
{
    public function __construct(private readonly HodReportService $hodReportService) {}

    public function departmentReport(HodDepartmentReportRequest $request): JsonResponse
    {
        Gate::authorize('viewAnyReport', Department::class);

        $actor = $request->user();
        $school = School::findOrFail(
            $actor->role === UserRole::SuperAdmin ? $request->validated('school_id') : $actor->school_id
        );

        $department = null;
        if ($request->validated('department_id') !== null) {
            $department = Department::findOrFail($request->validated('department_id'));
            Gate::authorize('viewReport', $department);
        }

        // Defaulting to "this month" means this month at the school.
        $month = $request->validated('month') ?? $school->clock()->now()->format('Y-m');

        return response()->json(
            $this->hodReportService->departmentReport($actor, $school, $department, $month, $request->only(['per_page']))
        );
    }
}
