<?php

namespace App\Http\Resources;

use App\Models\TransportTripEvent;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin TransportTripEvent
 */
class TripEventResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type->value,
            'stop_id' => $this->stop_id,
            'stop_name' => $this->stop_name,
            'student_id' => $this->student_id,
            'student_name' => $this->student_name,
            'recorded_by_name' => $this->whenLoaded('recordedBy', fn () => $this->recordedBy->name),
            'recorded_at' => $this->recorded_at,
            'note' => $this->note,
        ];
    }
}
