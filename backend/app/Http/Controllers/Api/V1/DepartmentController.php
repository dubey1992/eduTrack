<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Departments\StoreDepartmentRequest;
use App\Http\Requests\Departments\UpdateDepartmentRequest;
use App\Http\Resources\DepartmentResource;
use App\Models\Department;
use App\Services\DepartmentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class DepartmentController extends Controller
{
    public function __construct(private readonly DepartmentService $departmentService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Department::class);

        $departments = $this->departmentService->paginate($request->user(), $request->only(['school_id', 'per_page']));

        return DepartmentResource::collection($departments);
    }

    public function store(StoreDepartmentRequest $request): JsonResponse
    {
        $department = $this->departmentService->create($request->validated(), $request->user());
        $department->load(['school', 'hod']);

        return (new DepartmentResource($department))->response()->setStatusCode(201);
    }

    public function show(Department $department): DepartmentResource
    {
        Gate::authorize('view', $department);

        return new DepartmentResource($department->load(['school', 'hod']));
    }

    public function update(UpdateDepartmentRequest $request, Department $department): DepartmentResource
    {
        $department = $this->departmentService->update($department, $request->validated());

        return new DepartmentResource($department->load(['school', 'hod']));
    }

    public function destroy(Department $department): Response
    {
        Gate::authorize('delete', $department);
        $this->departmentService->delete($department);

        return response()->noContent();
    }
}
