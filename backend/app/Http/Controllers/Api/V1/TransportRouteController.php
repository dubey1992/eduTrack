<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Transport\StoreTransportRouteRequest;
use App\Http\Requests\Transport\StoreTransportStopRequest;
use App\Http\Requests\Transport\UpdateTransportRouteRequest;
use App\Http\Requests\Transport\UpdateTransportStopRequest;
use App\Http\Resources\RouteStudentResource;
use App\Http\Resources\TransportRouteResource;
use App\Http\Resources\TransportStopResource;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Services\StudentTransportService;
use App\Services\TransportRouteService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class TransportRouteController extends Controller
{
    public function __construct(
        private readonly TransportRouteService $routeService,
        private readonly StudentTransportService $studentTransportService,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', TransportRoute::class);

        $routes = $this->routeService->paginate($request->user(), $request->only(['school_id', 'status', 'per_page']));

        return TransportRouteResource::collection($routes);
    }

    public function store(StoreTransportRouteRequest $request): JsonResponse
    {
        $route = $this->routeService->create($request->validated(), $request->user());

        return (new TransportRouteResource($this->routeService->detail($route)))->response()->setStatusCode(201);
    }

    public function show(TransportRoute $route): TransportRouteResource
    {
        Gate::authorize('view', $route);

        return new TransportRouteResource($this->routeService->detail($route));
    }

    public function update(UpdateTransportRouteRequest $request, TransportRoute $route): TransportRouteResource
    {
        $route = $this->routeService->update($route, $request->validated());

        return new TransportRouteResource($this->routeService->detail($route));
    }

    public function destroy(TransportRoute $route): Response
    {
        Gate::authorize('delete', $route);
        $this->routeService->delete($route);

        return response()->noContent();
    }

    public function storeStop(StoreTransportStopRequest $request, TransportRoute $route): JsonResponse
    {
        $stop = $this->routeService->addStop($route, $request->validated());

        return (new TransportStopResource($stop->loadCount('assignments')))->response()->setStatusCode(201);
    }

    public function updateStop(UpdateTransportStopRequest $request, TransportStop $stop): TransportStopResource
    {
        $stop = $this->routeService->updateStop($stop, $request->validated());

        return new TransportStopResource($stop->loadCount('assignments'));
    }

    public function destroyStop(TransportStop $stop): Response
    {
        Gate::authorize('update', $stop->route);
        $this->routeService->deleteStop($stop);

        return response()->noContent();
    }

    public function students(Request $request, TransportRoute $route): AnonymousResourceCollection
    {
        Gate::authorize('viewStudents', $route);

        return RouteStudentResource::collection(
            $this->studentTransportService->studentsOnRoute($route, $request->only(['per_page']))
        );
    }
}
