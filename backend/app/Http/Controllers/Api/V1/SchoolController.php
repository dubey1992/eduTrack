<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Schools\StoreSchoolRequest;
use App\Http\Requests\Schools\UpdateSchoolRequest;
use App\Http\Resources\SchoolResource;
use App\Models\EarlyAccessRequest;
use App\Models\School;
use App\Services\EarlyAccessService;
use App\Services\SchoolService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class SchoolController extends Controller
{
    public function __construct(
        private readonly SchoolService $schoolService,
        private readonly EarlyAccessService $earlyAccess,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', School::class);

        return SchoolResource::collection(
            $this->schoolService->paginate($request->user(), $request->only(['per_page']))
        );
    }

    public function store(StoreSchoolRequest $request): JsonResponse
    {
        $data = $request->validated();
        $requestId = $data['early_access_request_id'] ?? null;
        unset($data['early_access_request_id']);

        $school = $this->schoolService->create($data);

        // Closing the loop: the signup request records the school it became,
        // which is the only way "Converted" can be true rather than
        // remembered.
        if ($requestId !== null) {
            $this->earlyAccess->markConverted(
                EarlyAccessRequest::findOrFail($requestId),
                $school,
                $request->user(),
            );
        }

        return (new SchoolResource($school))->response()->setStatusCode(201);
    }

    public function show(School $school): SchoolResource
    {
        Gate::authorize('view', $school);

        return new SchoolResource($school);
    }

    public function update(UpdateSchoolRequest $request, School $school): SchoolResource
    {
        return new SchoolResource($this->schoolService->update($school, $request->validated()));
    }

    public function activate(School $school): SchoolResource
    {
        Gate::authorize('setStatus', $school);

        return new SchoolResource($this->schoolService->activate($school));
    }

    public function deactivate(School $school): SchoolResource
    {
        Gate::authorize('setStatus', $school);

        return new SchoolResource($this->schoolService->deactivate($school));
    }
}
