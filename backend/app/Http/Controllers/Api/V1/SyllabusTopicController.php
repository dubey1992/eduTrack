<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Syllabus\StoreSyllabusTopicRequest;
use App\Http\Requests\Syllabus\UpdateSyllabusTopicRequest;
use App\Http\Resources\SyllabusTopicResource;
use App\Models\Subject;
use App\Models\SyllabusTopic;
use App\Services\SyllabusTopicService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class SyllabusTopicController extends Controller
{
    public function __construct(private readonly SyllabusTopicService $syllabusTopicService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', SyllabusTopic::class);

        $subject = Subject::findOrFail($request->validate(['subject_id' => ['required', 'integer', 'exists:subjects,id']])['subject_id']);

        return SyllabusTopicResource::collection($this->syllabusTopicService->forSubject($subject)->load('subject'));
    }

    public function store(StoreSyllabusTopicRequest $request): JsonResponse
    {
        $subject = $request->subject();
        Gate::authorize('create', [SyllabusTopic::class, $subject]);

        $topic = $this->syllabusTopicService->create($subject, $request->validated())->load('subject');

        return (new SyllabusTopicResource($topic))->response()->setStatusCode(201);
    }

    public function update(UpdateSyllabusTopicRequest $request, SyllabusTopic $syllabusTopic): SyllabusTopicResource
    {
        $topic = $this->syllabusTopicService->update($syllabusTopic, $request->validated())->load('subject');

        return new SyllabusTopicResource($topic);
    }

    public function destroy(SyllabusTopic $syllabusTopic): Response
    {
        Gate::authorize('delete', $syllabusTopic);
        $this->syllabusTopicService->delete($syllabusTopic);

        return response()->noContent();
    }
}
