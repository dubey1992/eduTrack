<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Syllabus\SyllabusChecklistRequest;
use App\Http\Requests\Syllabus\ToggleSyllabusProgressRequest;
use App\Models\ClassSection;
use App\Models\Subject;
use App\Models\SyllabusTopic;
use App\Services\SyllabusProgressService;
use App\Support\SchoolScope;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Gate;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

class SyllabusProgressController extends Controller
{
    public function __construct(private readonly SyllabusProgressService $syllabusProgressService) {}

    public function index(SyllabusChecklistRequest $request): JsonResponse
    {
        $section = ClassSection::with('schoolClass')->findOrFail($request->validated('class_section_id'));
        $subject = Subject::findOrFail($request->validated('subject_id'));
        Gate::authorize('viewChecklist', [SyllabusTopic::class, $section]);

        // The policy looks at the section. The subject arrives separately and
        // has to be checked separately: paired with one of the actor's own
        // sections, another school's subject would otherwise hand over that
        // school's topic list.
        if (! SchoolScope::for($request->user())->allows($subject->school_id)) {
            throw new NotFoundHttpException;
        }

        return response()->json($this->syllabusProgressService->checklist($subject, $section));
    }

    public function update(ToggleSyllabusProgressRequest $request): JsonResponse
    {
        $topic = SyllabusTopic::findOrFail($request->validated('syllabus_topic_id'));
        $section = ClassSection::with('schoolClass')->findOrFail($request->validated('class_section_id'));
        Gate::authorize('mark', [$topic, $section]);

        $this->syllabusProgressService->toggle($topic, $section, $request->boolean('completed'), $request->user());

        return response()->json($this->syllabusProgressService->checklist($topic->subject, $section));
    }
}
