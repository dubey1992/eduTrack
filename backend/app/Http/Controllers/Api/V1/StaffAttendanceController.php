<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\StaffAttendance\StaffAttendanceRegisterRequest;
use App\Http\Requests\StaffAttendance\StoreStaffAttendanceRequest;
use App\Http\Requests\StaffAttendance\UpdateStaffAttendanceRequest;
use App\Http\Resources\StaffAttendanceResource;
use App\Models\School;
use App\Models\StaffAttendance;
use App\Services\StaffAttendanceService;
use App\Support\SchoolScope;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class StaffAttendanceController extends Controller
{
    public function __construct(private readonly StaffAttendanceService $staffAttendanceService) {}

    public function register(StaffAttendanceRegisterRequest $request): JsonResponse
    {
        $school = $this->resolveSchool($request);
        Gate::authorize('manage', [StaffAttendance::class, $school]);

        return response()->json(
            $this->staffAttendanceService->register(
                $school,
                $request->validated('department_id'),
                $request->validated('date'),
                $request->user(),
            )
        );
    }

    public function store(StoreStaffAttendanceRequest $request): JsonResponse
    {
        $school = $this->resolveSchool($request);
        Gate::authorize('manage', [StaffAttendance::class, $school]);

        return response()->json(
            $this->staffAttendanceService->submit($school, $request->validated(), $request->user()),
            201
        );
    }

    public function update(UpdateStaffAttendanceRequest $request): JsonResponse
    {
        $school = $this->resolveSchool($request);
        Gate::authorize('manage', [StaffAttendance::class, $school]);

        return response()->json($this->staffAttendanceService->update($school, $request->validated(), $request->user()));
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', StaffAttendance::class);

        $attendances = $this->staffAttendanceService->paginate(
            $request->user(),
            $request->only(['school_id', 'staff_profile_id', 'department_id', 'status', 'date_from', 'date_to', 'per_page'])
        );

        return StaffAttendanceResource::collection($attendances);
    }

    /**
     * A SUPER_ADMIN must supply school_id explicitly; every other role is
     * always scoped to their own, regardless of what (if anything) they
     * passed - matches the pattern used across every other Phase 4-7
     * controller (never trust the client for tenant scoping).
     */
    private function resolveSchool(StaffAttendanceRegisterRequest|StoreStaffAttendanceRequest|UpdateStaffAttendanceRequest $request): School
    {
        $actor = $request->user();
        $schoolId = SchoolScope::for($actor)->writableSchoolId($request->integer('school_id') ?: null);

        return School::findOrFail($schoolId);
    }
}
