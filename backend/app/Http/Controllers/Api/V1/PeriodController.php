<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Periods\StorePeriodRequest;
use App\Http\Requests\Periods\UpdatePeriodRequest;
use App\Http\Resources\PeriodResource;
use App\Models\Period;
use App\Services\PeriodService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class PeriodController extends Controller
{
    public function __construct(private readonly PeriodService $periodService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Period::class);

        $periods = $this->periodService->list($request->user(), $request->only(['school_id']));

        return PeriodResource::collection($periods);
    }

    public function store(StorePeriodRequest $request): JsonResponse
    {
        $period = $this->periodService->create($request->validated(), $request->user());

        return (new PeriodResource($period))->response()->setStatusCode(201);
    }

    public function update(UpdatePeriodRequest $request, Period $period): PeriodResource
    {
        $period = $this->periodService->update($period, $request->validated());

        return new PeriodResource($period);
    }

    public function destroy(Period $period): Response
    {
        Gate::authorize('delete', $period);
        $this->periodService->delete($period);

        return response()->noContent();
    }
}
