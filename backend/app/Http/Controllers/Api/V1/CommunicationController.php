<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\MessageEvent;
use App\Exceptions\MessageNotRetryableException;
use App\Http\Controllers\Controller;
use App\Http\Requests\Communication\MessageIndexRequest;
use App\Http\Requests\Communication\UpdateCommunicationSettingRequest;
use App\Http\Requests\Communication\UpdateMessageTemplateRequest;
use App\Http\Resources\CommunicationSettingResource;
use App\Http\Resources\MessageResource;
use App\Http\Resources\MessageTemplateResource;
use App\Models\Message;
use App\Models\School;
use App\Services\CommunicationSettingService;
use App\Services\MessageService;
use App\Services\MessageTemplateService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

/**
 * The prototype's Communication Center: the message log, its KPI tiles, the
 * template manager and the alert switches.
 */
class CommunicationController extends Controller
{
    public function __construct(
        private readonly MessageService $messages,
        private readonly MessageTemplateService $templates,
        private readonly CommunicationSettingService $settings,
    ) {}

    public function index(MessageIndexRequest $request): AnonymousResourceCollection
    {
        return MessageResource::collection(
            $this->messages->paginate($request->user(), $request->validated())
        );
    }

    public function summary(MessageIndexRequest $request): JsonResponse
    {
        return response()->json($this->messages->summary($request->user(), $request->validated()));
    }

    public function show(Message $message): MessageResource
    {
        Gate::authorize('view', $message);

        return new MessageResource($message);
    }

    /**
     * Only a failed message can be re-sent. Anything else would either
     * duplicate a delivered message or fight with the queue.
     */
    public function retry(Message $message): MessageResource
    {
        Gate::authorize('retry', $message);

        if (! $message->isRetryable()) {
            throw new MessageNotRetryableException('Only a failed message can be sent again.');
        }

        return new MessageResource($this->messages->retry($message));
    }

    public function templates(Request $request): AnonymousResourceCollection
    {
        $schoolId = $this->resolveSchoolId($request);
        Gate::authorize('configure', [Message::class, $schoolId]);

        return MessageTemplateResource::collection($this->templates->listFor($schoolId));
    }

    public function updateTemplate(UpdateMessageTemplateRequest $request, string $event): MessageTemplateResource
    {
        $messageEvent = $request->event();
        abort_if($messageEvent === null, Response::HTTP_NOT_FOUND);

        $school = School::findOrFail($request->schoolId());
        $this->templates->update($school, $messageEvent, $request->validated('body'), $request->user());

        return $this->templateFor($school->id, $messageEvent);
    }

    /**
     * Drops a school's override so the event falls back to its shipped wording.
     */
    public function resetTemplate(Request $request, string $event): MessageTemplateResource
    {
        $messageEvent = MessageEvent::tryFrom($event);
        abort_if($messageEvent === null, Response::HTTP_NOT_FOUND);

        $schoolId = $this->resolveSchoolId($request);
        Gate::authorize('configure', [Message::class, $schoolId]);

        $this->templates->reset(School::findOrFail($schoolId), $messageEvent);

        return $this->templateFor($schoolId, $messageEvent);
    }

    public function settings(Request $request): CommunicationSettingResource
    {
        $schoolId = $this->resolveSchoolId($request);
        Gate::authorize('configure', [Message::class, $schoolId]);

        return new CommunicationSettingResource($this->settings->for($schoolId));
    }

    /**
     * Settings are a singleton per school, so saving them for the first time
     * is still a 200 - there is no new address to point a client at.
     */
    public function updateSettings(UpdateCommunicationSettingRequest $request): JsonResponse
    {
        $school = School::findOrFail($request->schoolId());
        $setting = $this->settings->update($school, $request->validated());

        return (new CommunicationSettingResource($setting))->response()->setStatusCode(Response::HTTP_OK);
    }

    private function templateFor(int $schoolId, MessageEvent $event): MessageTemplateResource
    {
        $row = $this->templates->listFor($schoolId)->firstWhere('event', $event);

        return new MessageTemplateResource($row);
    }

    /**
     * A Super Admin works school by school; everyone else is pinned to theirs.
     */
    private function resolveSchoolId(Request $request): int
    {
        $requested = $request->query('school_id');

        return $requested === null ? (int) $request->user()->school_id : (int) $requested;
    }
}
