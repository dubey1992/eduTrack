<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\AcademicYears\StoreAcademicYearRequest;
use App\Http\Requests\AcademicYears\UpdateAcademicYearRequest;
use App\Http\Resources\AcademicYearResource;
use App\Models\AcademicYear;
use App\Services\AcademicYearService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class AcademicYearController extends Controller
{
    public function __construct(private readonly AcademicYearService $academicYearService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', AcademicYear::class);

        $years = $this->academicYearService->paginate($request->user(), $request->only(['school_id', 'per_page']));

        return AcademicYearResource::collection($years);
    }

    public function store(StoreAcademicYearRequest $request): JsonResponse
    {
        $academicYear = $this->academicYearService->create($request->validated(), $request->user());
        $academicYear->load('school');

        return (new AcademicYearResource($academicYear))->response()->setStatusCode(201);
    }

    public function show(AcademicYear $academicYear): AcademicYearResource
    {
        Gate::authorize('view', $academicYear);

        return new AcademicYearResource($academicYear->load('school'));
    }

    public function update(UpdateAcademicYearRequest $request, AcademicYear $academicYear): AcademicYearResource
    {
        $academicYear = $this->academicYearService->update($academicYear, $request->validated());

        return new AcademicYearResource($academicYear->load('school'));
    }

    public function setCurrent(AcademicYear $academicYear): AcademicYearResource
    {
        Gate::authorize('setCurrent', $academicYear);

        $academicYear = $this->academicYearService->setCurrent($academicYear);

        return new AcademicYearResource($academicYear->load('school'));
    }

    public function destroy(AcademicYear $academicYear): Response
    {
        Gate::authorize('delete', $academicYear);
        $this->academicYearService->delete($academicYear);

        return response()->noContent();
    }
}
