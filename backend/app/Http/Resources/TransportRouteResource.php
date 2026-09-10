<?php

namespace App\Http\Resources;

use App\Models\TransportRoute;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin TransportRoute
 */
class TransportRouteResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'school_name' => $this->whenLoaded('school', fn () => $this->school->name),
            'name' => $this->name,
            'label' => $this->label(),
            'status' => $this->status->value,
            'vehicle_id' => $this->vehicle_id,
            'vehicle_name' => $this->vehicle?->name,
            'vehicle_registration_number' => $this->vehicle?->registration_number,
            'capacity' => $this->vehicle?->capacity,
            'driver_id' => $this->driver_id,
            'driver_name' => $this->driver?->name,
            'driver_mobile' => $this->driver?->mobile,
            'stops_count' => $this->whenCounted('stops'),
            'students_count' => $this->whenCounted('assignments'),
            'stops' => TransportStopResource::collection($this->whenLoaded('stops')),
            'created_at' => $this->created_at,
        ];
    }
}
