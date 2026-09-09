<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Holidays\StoreHolidayRequest;
use App\Http\Requests\Holidays\UpdateHolidayRequest;
use App\Http\Resources\HolidayResource;
use App\Models\Holiday;
use App\Services\HolidayService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class HolidayController extends Controller
{
    public function __construct(private readonly HolidayService $holidayService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Holiday::class);

        $holidays = $this->holidayService->paginate(
            $request->user(),
            $request->only(['school_id', 'date_from', 'date_to', 'per_page'])
        );

        return HolidayResource::collection($holidays);
    }

    public function store(StoreHolidayRequest $request): JsonResponse
    {
        $holiday = $this->holidayService->create($request->validated(), $request->user());

        return (new HolidayResource($holiday->load('school')))->response()->setStatusCode(201);
    }

    public function show(Holiday $holiday): HolidayResource
    {
        Gate::authorize('view', $holiday);

        return new HolidayResource($holiday->load('school'));
    }

    public function update(UpdateHolidayRequest $request, Holiday $holiday): HolidayResource
    {
        $holiday = $this->holidayService->update($holiday, $request->validated());

        return new HolidayResource($holiday->load('school'));
    }

    public function destroy(Holiday $holiday): Response
    {
        Gate::authorize('delete', $holiday);
        $this->holidayService->delete($holiday);

        return response()->noContent();
    }
}
