<?php

namespace App\Http\Resources;

use App\Models\Driver;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Driver
 */
class DriverResource extends JsonResource
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
            'mobile' => $this->mobile,
            'licence_number' => $this->licence_number,
            'licence_expiry' => $this->licence_expiry?->toDateString(),
            'status' => $this->status->value,
            'route_id' => $this->whenLoaded('route', fn () => $this->route?->id),
            'route_name' => $this->whenLoaded('route', fn () => $this->route?->name),
            'created_at' => $this->created_at,
        ];
    }
}
