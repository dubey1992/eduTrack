<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\AnnouncementAudience;
use App\Enums\AnnouncementChannels;
use App\Http\Controllers\Controller;
use App\Http\Requests\Announcements\PublishAnnouncementRequest;
use App\Http\Resources\AnnouncementResource;
use App\Models\Announcement;
use App\Services\AnnouncementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

/**
 * Phase 17 - the prototype's "New Announcement" flow plus the list of what
 * has been published. Reading an announcement as a recipient is the inbox.
 */
class AnnouncementController extends Controller
{
    public function __construct(private readonly AnnouncementService $announcements) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Announcement::class);

        return AnnouncementResource::collection(
            $this->announcements->paginate(
                $request->user(),
                $request->only(['school_id', 'audience_type', 'q', 'active_only', 'per_page'])
            )
        );
    }

    public function store(PublishAnnouncementRequest $request): JsonResponse
    {
        $announcement = $this->announcements->publish($request->payload(), $request->user());

        return (new AnnouncementResource($announcement))->response()->setStatusCode(Response::HTTP_CREATED);
    }

    public function show(Announcement $announcement): AnnouncementResource
    {
        Gate::authorize('view', $announcement);

        return new AnnouncementResource($announcement->load(['school', 'publishedBy']));
    }

    public function destroy(Announcement $announcement): Response
    {
        Gate::authorize('delete', $announcement);
        $this->announcements->delete($announcement);

        return response()->noContent();
    }

    /**
     * How many people a given audience would reach, so the compose form can
     * say "goes to 312 people" before anything is sent.
     */
    public function preview(Request $request): JsonResponse
    {
        Gate::authorize('viewAny', Announcement::class);

        $audience = AnnouncementAudience::tryFrom((string) $request->query('audience_type'));
        $channels = AnnouncementChannels::tryFrom((string) $request->query('channels'));
        abort_if($audience === null || $channels === null, Response::HTTP_UNPROCESSABLE_ENTITY);

        $schoolId = (int) ($request->query('school_id') ?? $request->user()->school_id);
        $target = $request->query('audience_id') === null ? null : (int) $request->query('audience_id');

        Gate::authorize('publish', [Announcement::class, $audience, $target, $schoolId]);

        return response()->json([
            ...$this->announcements->countRecipients($schoolId, $audience, $target, $channels),
            'audience_label' => $this->announcements->audienceLabel($audience, $target),
        ]);
    }
}
