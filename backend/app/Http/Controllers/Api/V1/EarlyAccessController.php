<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\EarlyAccess\ReviewEarlyAccessRequest;
use App\Http\Requests\EarlyAccess\StoreEarlyAccessRequest;
use App\Http\Resources\EarlyAccessRequestResource;
use App\Models\EarlyAccessRequest;
use App\Services\EarlyAccessService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class EarlyAccessController extends Controller
{
    public function __construct(private readonly EarlyAccessService $earlyAccess) {}

    /**
     * The marketing page's form. The only write in the API that needs no
     * account - it is how a school without one asks for access.
     *
     * Answers the same way whether the request was new or an update to one
     * already open: the person filling it in is told we have their details,
     * and nothing about who else has already asked.
     */
    public function store(StoreEarlyAccessRequest $request): JsonResponse
    {
        $this->earlyAccess->record($request->validated());

        return response()->json([
            'message' => 'Thanks - we have your details and will be in touch soon.',
        ], 201);
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', EarlyAccessRequest::class);

        return EarlyAccessRequestResource::collection(
            $this->earlyAccess->paginate($request->only(['status', 'q', 'per_page']))
        );
    }

    public function show(EarlyAccessRequest $earlyAccessRequest): EarlyAccessRequestResource
    {
        Gate::authorize('view', $earlyAccessRequest);

        return new EarlyAccessRequestResource($earlyAccessRequest->load(['convertedSchool', 'reviewedBy']));
    }

    public function review(ReviewEarlyAccessRequest $request, EarlyAccessRequest $earlyAccessRequest): EarlyAccessRequestResource
    {
        return new EarlyAccessRequestResource(
            $this->earlyAccess->review($earlyAccessRequest, $request->validated(), $request->user())
        );
    }
}
