<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Staff\StoreStaffRequest;
use App\Http\Requests\Staff\UpdateStaffProfileRequest;
use App\Http\Resources\StaffProfileResource;
use App\Models\StaffProfile;
use App\Services\StaffProfileService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class StaffController extends Controller
{
    public function __construct(private readonly StaffProfileService $staffProfileService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', StaffProfile::class);

        $staff = $this->staffProfileService->paginate(
            $request->user(),
            $request->only(['school_id', 'department_id', 'role', 'status', 'search', 'per_page'])
        );

        return StaffProfileResource::collection($staff);
    }

    public function store(StoreStaffRequest $request): JsonResponse
    {
        $staffProfile = $this->staffProfileService->createEmployee(
            $request->userData(),
            $request->profileData(),
            $request->user(),
        );

        return (new StaffProfileResource($staffProfile))->response()->setStatusCode(201);
    }

    public function show(StaffProfile $staffProfile): StaffProfileResource
    {
        Gate::authorize('view', $staffProfile);

        return new StaffProfileResource($staffProfile->load(['user.classTeacherOf.schoolClass', 'school', 'department']));
    }

    public function update(UpdateStaffProfileRequest $request, StaffProfile $staffProfile): StaffProfileResource
    {
        $staffProfile = $this->staffProfileService->update($staffProfile, $request->validated());

        return new StaffProfileResource($staffProfile->load(['user.classTeacherOf.schoolClass', 'school', 'department']));
    }
}
