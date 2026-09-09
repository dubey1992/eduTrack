<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Subjects\StoreSubjectRequest;
use App\Http\Requests\Subjects\UpdateSubjectRequest;
use App\Http\Resources\SubjectResource;
use App\Models\Subject;
use App\Services\SubjectService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class SubjectController extends Controller
{
    public function __construct(private readonly SubjectService $subjectService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Subject::class);

        $subjects = $this->subjectService->paginate(
            $request->user(),
            $request->only(['school_id', 'department_id', 'per_page'])
        );

        return SubjectResource::collection($subjects);
    }

    public function store(StoreSubjectRequest $request): JsonResponse
    {
        $subject = $this->subjectService->create($request->validated(), $request->user());
        $subject->load(['school', 'department', 'leadTeacher']);

        return (new SubjectResource($subject))->response()->setStatusCode(201);
    }

    public function show(Subject $subject): SubjectResource
    {
        Gate::authorize('view', $subject);

        return new SubjectResource($subject->load(['school', 'department', 'leadTeacher']));
    }

    public function update(UpdateSubjectRequest $request, Subject $subject): SubjectResource
    {
        $subject = $this->subjectService->update($subject, $request->validated());

        return new SubjectResource($subject->load(['school', 'department', 'leadTeacher']));
    }

    public function destroy(Subject $subject): Response
    {
        Gate::authorize('delete', $subject);
        $this->subjectService->delete($subject);

        return response()->noContent();
    }
}
