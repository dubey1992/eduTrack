<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\SchoolClasses\StoreClassSectionRequest;
use App\Http\Requests\SchoolClasses\StoreSchoolClassRequest;
use App\Http\Requests\SchoolClasses\UpdateClassSectionRequest;
use App\Http\Requests\SchoolClasses\UpdateSchoolClassRequest;
use App\Http\Resources\ClassSectionResource;
use App\Http\Resources\SchoolClassResource;
use App\Models\ClassSection;
use App\Models\SchoolClass;
use App\Services\SchoolClassService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class SchoolClassController extends Controller
{
    public function __construct(private readonly SchoolClassService $schoolClassService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', SchoolClass::class);

        $classes = $this->schoolClassService->paginate(
            $request->user(),
            $request->only(['school_id', 'academic_year_id', 'per_page'])
        );

        return SchoolClassResource::collection($classes);
    }

    public function store(StoreSchoolClassRequest $request): JsonResponse
    {
        $schoolClass = $this->schoolClassService->create($request->validated(), $request->user());
        $schoolClass->load(['school', 'academicYear', 'sections.classTeacher']);

        return (new SchoolClassResource($schoolClass))->response()->setStatusCode(201);
    }

    public function show(SchoolClass $schoolClass): SchoolClassResource
    {
        Gate::authorize('view', $schoolClass);

        return new SchoolClassResource($schoolClass->load(['school', 'academicYear', 'sections.classTeacher']));
    }

    public function update(UpdateSchoolClassRequest $request, SchoolClass $schoolClass): SchoolClassResource
    {
        $schoolClass = $this->schoolClassService->update($schoolClass, $request->validated());

        return new SchoolClassResource($schoolClass->load(['school', 'academicYear', 'sections.classTeacher']));
    }

    public function destroy(SchoolClass $schoolClass): Response
    {
        Gate::authorize('delete', $schoolClass);
        $this->schoolClassService->delete($schoolClass);

        return response()->noContent();
    }

    public function addSection(StoreClassSectionRequest $request, SchoolClass $schoolClass): JsonResponse
    {
        $section = $this->schoolClassService->addSection($schoolClass, $request->validated());
        $section->load('classTeacher');

        return (new ClassSectionResource($section))->response()->setStatusCode(201);
    }

    public function updateSection(UpdateClassSectionRequest $request, ClassSection $section): ClassSectionResource
    {
        $section = $this->schoolClassService->updateSection($section, $request->validated());

        return new ClassSectionResource($section->load('classTeacher'));
    }

    public function deleteSection(ClassSection $section): Response
    {
        Gate::authorize('delete', $section);
        $this->schoolClassService->deleteSection($section);

        return response()->noContent();
    }
}
