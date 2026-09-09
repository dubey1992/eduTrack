<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\TeachingReports\StoreDailyTeachingReportRequest;
use App\Http\Resources\DailyTeachingReportResource;
use App\Models\DailyTeachingReport;
use App\Models\TimetableEntry;
use App\Services\DailyTeachingReportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class DailyTeachingReportController extends Controller
{
    public function __construct(private readonly DailyTeachingReportService $teachingReportService) {}

    public function store(StoreDailyTeachingReportRequest $request): JsonResponse
    {
        $entry = TimetableEntry::findOrFail($request->validated('timetable_entry_id'));
        Gate::authorize('create', [DailyTeachingReport::class, $entry]);

        $report = $this->teachingReportService->create($entry, $request->validated(), $request->user());

        return response()->json(new DailyTeachingReportResource($report), 201);
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', DailyTeachingReport::class);

        $reports = $this->teachingReportService->paginate(
            $request->user(),
            $request->only(['school_id', 'teacher_id', 'report_date', 'per_page'])
        );

        return DailyTeachingReportResource::collection($reports);
    }

    public function summary(Request $request): JsonResponse
    {
        Gate::authorize('viewAny', DailyTeachingReport::class);
        $date = $request->validate(['date' => ['required', 'date']])['date'];

        return response()->json(
            $this->teachingReportService->summary($request->user(), $request->only(['school_id']), $date)
        );
    }

    public function review(Request $request, DailyTeachingReport $report): DailyTeachingReportResource
    {
        Gate::authorize('review', $report);

        return new DailyTeachingReportResource($this->teachingReportService->review($report, $request->user()));
    }
}
