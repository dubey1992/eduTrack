<?php

namespace App\Http\Controllers\Api\V1;

use App\Exceptions\StaffProfileRequiredException;
use App\Http\Controllers\Controller;
use App\Http\Requests\StaffLeave\ApplyStaffLeaveRequest;
use App\Http\Requests\StaffLeave\ReviewStaffLeaveRequest;
use App\Http\Resources\StaffLeaveResource;
use App\Models\StaffLeave;
use App\Services\StaffLeaveService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class StaffLeaveController extends Controller
{
    public function __construct(private readonly StaffLeaveService $staffLeaveService) {}

    public function store(ApplyStaffLeaveRequest $request): JsonResponse
    {
        Gate::authorize('apply', StaffLeave::class);

        $staffProfile = $request->user()->staffProfile;
        if ($staffProfile === null) {
            throw new StaffProfileRequiredException(
                'Your account is not yet linked to a staff profile. Ask your school admin to add you under '.
                'Teachers & Staff before applying for leave.'
            );
        }

        $leave = $this->staffLeaveService->apply($staffProfile, $request->validated(), $request->user());

        return response()->json(new StaffLeaveResource($leave), 201);
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', StaffLeave::class);

        $leaves = $this->staffLeaveService->paginate(
            $request->user(),
            $request->only(['school_id', 'staff_profile_id', 'department_id', 'status', 'per_page'])
        );

        return StaffLeaveResource::collection($leaves);
    }

    public function summary(Request $request): JsonResponse
    {
        Gate::authorize('viewAny', StaffLeave::class);

        return response()->json($this->staffLeaveService->summary($request->user(), $request->only(['school_id'])));
    }

    public function approve(ReviewStaffLeaveRequest $request, StaffLeave $leave): JsonResponse
    {
        Gate::authorize('review', $leave);

        $reviewed = $this->staffLeaveService->approve($leave, $request->user(), $request->validated('remarks'));

        return response()->json(new StaffLeaveResource($reviewed));
    }

    public function reject(ReviewStaffLeaveRequest $request, StaffLeave $leave): JsonResponse
    {
        Gate::authorize('review', $leave);

        $reviewed = $this->staffLeaveService->reject($leave, $request->user(), $request->validated('remarks'));

        return response()->json(new StaffLeaveResource($reviewed));
    }
}
