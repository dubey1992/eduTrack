<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Schools\StoreSchoolRequest;
use App\Http\Requests\Schools\UpdateSchoolRequest;
use App\Http\Resources\SchoolResource;
use App\Models\School;
use App\Services\SchoolService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class SchoolController extends Controller
{
    public function __construct(private readonly SchoolService $schoolService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', School::class);

        return SchoolResource::collection($this->schoolService->paginate($request->only(['per_page'])));
    }

    public function store(StoreSchoolRequest $request): JsonResponse
    {
        $school = $this->schoolService->create($request->validated());

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
