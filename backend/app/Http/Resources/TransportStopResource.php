<?php

namespace App\Http\Resources;

use App\Models\TransportStop;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin TransportStop
 */
class TransportStopResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'route_id' => $this->route_id,
            'name' => $this->name,
            'sequence_number' => $this->sequence_number,
            'pickup_time' => $this->pickup_time === null ? null : substr($this->pickup_time, 0, 5),
            'drop_time' => $this->drop_time === null ? null : substr($this->drop_time, 0, 5),
            'students_count' => $this->whenCounted('assignments'),
        ];
    }
}
