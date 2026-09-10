<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Transport\StoreVehicleRequest;
use App\Http\Requests\Transport\UpdateVehicleRequest;
use App\Http\Resources\VehicleResource;
use App\Models\Vehicle;
use App\Services\VehicleService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class VehicleController extends Controller
{
    public function __construct(private readonly VehicleService $vehicleService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Vehicle::class);

        $vehicles = $this->vehicleService->paginate($request->user(), $request->only(['school_id', 'status', 'per_page']));

        return VehicleResource::collection($vehicles);
    }

    public function store(StoreVehicleRequest $request): JsonResponse
    {
        $vehicle = $this->vehicleService->create($request->validated(), $request->user());

        return (new VehicleResource($vehicle->load(['school', 'route'])))->response()->setStatusCode(201);
    }

    public function show(Vehicle $vehicle): VehicleResource
    {
        Gate::authorize('view', $vehicle);

        return new VehicleResource($vehicle->load(['school', 'route']));
    }

    public function update(UpdateVehicleRequest $request, Vehicle $vehicle): VehicleResource
    {
        $vehicle = $this->vehicleService->update($vehicle, $request->validated());

        return new VehicleResource($vehicle->load(['school', 'route']));
    }

    public function destroy(Vehicle $vehicle): Response
    {
        Gate::authorize('delete', $vehicle);
        $this->vehicleService->delete($vehicle);

        return response()->noContent();
    }
}
