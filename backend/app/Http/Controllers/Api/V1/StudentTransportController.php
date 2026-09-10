<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Transport\AssignStudentTransportRequest;
use App\Http\Resources\StudentResource;
use App\Models\Student;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Services\StudentTransportService;
use Illuminate\Support\Facades\Gate;

class StudentTransportController extends Controller
{
    private const array WITH = ['school', 'classSection.schoolClass', 'transportAssignment.route.vehicle', 'transportAssignment.stop'];

    public function __construct(private readonly StudentTransportService $studentTransportService) {}

    public function assign(AssignStudentTransportRequest $request, Student $student): StudentResource
    {
        $route = TransportRoute::with('vehicle')->findOrFail($request->validated('route_id'));
        $stop = TransportStop::findOrFail($request->validated('transport_stop_id'));

        $this->studentTransportService->assign($student, $route, $stop);

        return new StudentResource($student->fresh(self::WITH));
    }

    public function unassign(Student $student): StudentResource
    {
        Gate::authorize('update', $student);
        $this->studentTransportService->unassign($student);

        return new StudentResource($student->fresh(self::WITH));
    }
}
