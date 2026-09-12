<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\MessageResource;
use App\Models\Message;
use App\Services\MessageService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;

/**
 * A user's own in-app messages. No policy here on purpose - every query is
 * pinned to the authenticated user, so there is nothing to authorize beyond
 * being signed in.
 */
class InboxController extends Controller
{
    public function __construct(private readonly MessageService $messages) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return MessageResource::collection(
            $this->messages->inbox($request->user(), $request->only(['unread', 'per_page']))
        );
    }

    public function unreadCount(Request $request): JsonResponse
    {
        return response()->json(['unread' => $this->messages->unreadCount($request->user())]);
    }

    public function markRead(Request $request, Message $message): MessageResource
    {
        abort_if($message->user_id !== $request->user()->id, Response::HTTP_FORBIDDEN);

        return new MessageResource($this->messages->markRead($message));
    }

    public function markAllRead(Request $request): JsonResponse
    {
        return response()->json(['marked' => $this->messages->markAllRead($request->user())]);
    }
}
