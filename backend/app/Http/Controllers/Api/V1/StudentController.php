<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Students\StoreStudentRequest;
use App\Http\Requests\Students\UpdateStudentRequest;
use App\Http\Resources\StudentResource;
use App\Models\Student;
use App\Services\StudentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class StudentController extends Controller
{
    public function __construct(private readonly StudentService $studentService) {}

    private const WITH = ['school', 'classSection.schoolClass'];

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Student::class);

        $students = $this->studentService->paginate(
            $request->user(),
            $request->only(['school_id', 'class_section_id', 'status', 'search', 'per_page'])
        );

        return StudentResource::collection($students);
    }

    public function store(StoreStudentRequest $request): JsonResponse
    {
        $student = $this->studentService->create($request->validated(), $request->user());
        $student->load(self::WITH);

        return (new StudentResource($student))->response()->setStatusCode(201);
    }

    public function show(Student $student): StudentResource
    {
        Gate::authorize('view', $student);

        return new StudentResource($student->load(self::WITH));
    }

    public function update(UpdateStudentRequest $request, Student $student): StudentResource
    {
        $student = $this->studentService->update($student, $request->validated());

        return new StudentResource($student->load(self::WITH));
    }

    public function activate(Student $student): StudentResource
    {
        Gate::authorize('setStatus', $student);

        return new StudentResource($this->studentService->activate($student)->load(self::WITH));
    }

    public function deactivate(Student $student): StudentResource
    {
        Gate::authorize('setStatus', $student);

        return new StudentResource($this->studentService->deactivate($student)->load(self::WITH));
    }
}
