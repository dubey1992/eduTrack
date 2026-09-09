<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Http\Requests\Timetable\TimetableGridRequest;
use App\Http\Requests\Timetable\UpsertTimetableEntryRequest;
use App\Http\Resources\TimetableEntryResource;
use App\Models\ClassSection;
use App\Models\School;
use App\Models\TimetableEntry;
use App\Models\User;
use App\Services\TimetableService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

class TimetableController extends Controller
{
    public function __construct(private readonly TimetableService $timetableService) {}

    public function grid(TimetableGridRequest $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', TimetableEntry::class);
        $actor = $request->user();

        if ($request->filled('class_section_id')) {
            $classSection = ClassSection::with('schoolClass')->findOrFail($request->integer('class_section_id'));
            $this->assertSameSchool($actor, $classSection->schoolClass->school_id);
            $entries = $this->timetableService->forClassSection($classSection);
        } else {
            $teacher = User::findOrFail($request->integer('teacher_id'));
            $this->assertSameSchool($actor, $teacher->school_id);
            $entries = $this->timetableService->forTeacher($teacher);
        }

        return TimetableEntryResource::collection($entries);
    }

    public function upsert(UpsertTimetableEntryRequest $request): JsonResponse
    {
        $school = $this->resolveSchool($request);
        Gate::authorize('manage', [TimetableEntry::class, $school]);

        $entry = $this->timetableService->upsertEntry([...$request->validated(), 'school_id' => $school->id]);

        return response()->json(new TimetableEntryResource($entry), 201);
    }

    public function destroy(TimetableEntry $entry): Response
    {
        Gate::authorize('delete', $entry);
        $this->timetableService->deleteEntry($entry);

        return response()->noContent();
    }

    /**
     * A non-SUPER_ADMIN actor only ever reaches their own school's grid,
     * regardless of which class section/teacher id they asked for -
     * never trusted from the client.
     */
    private function assertSameSchool(User $actor, ?int $schoolId): void
    {
        if ($actor->role !== UserRole::SuperAdmin && $actor->school_id !== $schoolId) {
            throw new NotFoundHttpException;
        }
    }

    private function resolveSchool(UpsertTimetableEntryRequest $request): School
    {
        $actor = $request->user();
        $schoolId = $actor->role === UserRole::SuperAdmin ? $request->validated('school_id') : $actor->school_id;

        return School::findOrFail($schoolId);
    }
}
