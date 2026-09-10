<?php

namespace App\Http\Resources;

use App\Models\Vehicle;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Vehicle
 */
class VehicleResource extends JsonResource
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
            'registration_number' => $this->registration_number,
            'capacity' => $this->capacity,
            'status' => $this->status->value,
            'route_id' => $this->whenLoaded('route', fn () => $this->route?->id),
            'route_name' => $this->whenLoaded('route', fn () => $this->route?->name),
            'created_at' => $this->created_at,
        ];
    }
}
