<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\TripDirection;
use App\Enums\TripRiderStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Transport\StartTripRequest;
use App\Http\Requests\Transport\UpdateTripRiderRequest;
use App\Http\Resources\TransportTripResource;
use App\Models\Student;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Models\TransportTrip;
use App\Services\TransportTripService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\ValidationException;

class TransportTripController extends Controller
{
    public function __construct(private readonly TransportTripService $tripService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', TransportTrip::class);

        $trips = $this->tripService->paginate(
            $request->user(),
            $request->only(['school_id', 'route_id', 'date', 'status', 'per_page'])
        );

        return TransportTripResource::collection($trips);
    }

    public function store(StartTripRequest $request): JsonResponse
    {
        $route = TransportRoute::findOrFail($request->validated('route_id'));
        Gate::authorize('create', [TransportTrip::class, $route]);

        $trip = $this->tripService->start($route, TripDirection::from($request->validated('direction')), $request->user());

        return (new TransportTripResource($trip))->response()->setStatusCode(201);
    }

    public function show(TransportTrip $trip): TransportTripResource
    {
        Gate::authorize('view', $trip);

        return new TransportTripResource($this->tripService->detail($trip));
    }

    public function reachStop(Request $request, TransportTrip $trip, TransportStop $stop): TransportTripResource
    {
        Gate::authorize('manage', $trip);
        if ($stop->route_id !== $trip->route_id) {
            throw ValidationException::withMessages(['stop' => 'The selected stop is not on this trip\'s route.']);
        }

        return new TransportTripResource($this->tripService->reachStop($trip, $stop, $request->user()));
    }

    public function updateRider(UpdateTripRiderRequest $request, TransportTrip $trip, Student $student): TransportTripResource
    {
        if (! $trip->riders()->where('student_id', $student->id)->exists()) {
            throw ValidationException::withMessages(['student' => 'This student is not on this trip.']);
        }

        $status = TripRiderStatus::from($request->validated('status'));

        return new TransportTripResource($this->tripService->updateRider($trip, $student, $status, $request->user()));
    }

    public function end(Request $request, TransportTrip $trip): TransportTripResource
    {
        Gate::authorize('manage', $trip);

        return new TransportTripResource($this->tripService->end($trip, $request->user()));
    }

    public function cancel(Request $request, TransportTrip $trip): TransportTripResource
    {
        Gate::authorize('manage', $trip);

        return new TransportTripResource($this->tripService->cancel($trip, $request->user()));
    }
}
