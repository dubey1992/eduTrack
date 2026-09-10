<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Transport\StoreDriverRequest;
use App\Http\Requests\Transport\UpdateDriverRequest;
use App\Http\Resources\DriverResource;
use App\Models\Driver;
use App\Services\DriverService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class DriverController extends Controller
{
    public function __construct(private readonly DriverService $driverService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Driver::class);

        $drivers = $this->driverService->paginate($request->user(), $request->only(['school_id', 'status', 'per_page']));

        return DriverResource::collection($drivers);
    }

    public function store(StoreDriverRequest $request): JsonResponse
    {
        $driver = $this->driverService->create($request->validated(), $request->user());

        return (new DriverResource($driver->load(['school', 'route'])))->response()->setStatusCode(201);
    }

    public function show(Driver $driver): DriverResource
    {
        Gate::authorize('view', $driver);

        return new DriverResource($driver->load(['school', 'route']));
    }

    public function update(UpdateDriverRequest $request, Driver $driver): DriverResource
    {
        $driver = $this->driverService->update($driver, $request->validated());

        return new DriverResource($driver->load(['school', 'route']));
    }

    public function destroy(Driver $driver): Response
    {
        Gate::authorize('delete', $driver);
        $this->driverService->delete($driver);

        return response()->noContent();
    }
}
