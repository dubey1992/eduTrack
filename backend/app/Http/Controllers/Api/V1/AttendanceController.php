<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Attendance\AttendanceRegisterRequest;
use App\Http\Requests\Attendance\StoreAttendanceRequest;
use App\Http\Requests\Attendance\UpdateAttendanceRequest;
use App\Http\Resources\AttendanceResource;
use App\Models\Attendance;
use App\Models\ClassSection;
use App\Services\AttendanceService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class AttendanceController extends Controller
{
    public function __construct(private readonly AttendanceService $attendanceService) {}

    public function register(AttendanceRegisterRequest $request): JsonResponse
    {
        $section = ClassSection::with('schoolClass')->findOrFail($request->validated('class_section_id'));
        Gate::authorize('viewAttendance', $section);

        return response()->json($this->attendanceService->register($section, $request->validated('date')));
    }

    public function store(StoreAttendanceRequest $request): JsonResponse
    {
        $section = ClassSection::with('schoolClass')->findOrFail($request->validated('class_section_id'));
        Gate::authorize('markAttendance', $section);

        return response()->json(
            $this->attendanceService->submit($section, $request->validated(), $request->user()),
            201
        );
    }

    public function update(UpdateAttendanceRequest $request): JsonResponse
    {
        $section = ClassSection::with('schoolClass')->findOrFail($request->validated('class_section_id'));
        Gate::authorize('markAttendance', $section);

        return response()->json($this->attendanceService->update($section, $request->validated(), $request->user()));
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Attendance::class);

        $attendances = $this->attendanceService->paginate(
            $request->user(),
            $request->only(['school_id', 'class_section_id', 'student_id', 'status', 'date_from', 'date_to'])
        );

        return AttendanceResource::collection($attendances);
    }
}
