<?php

namespace App\Http\Resources;

use App\Models\School;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin School
 */
class SchoolResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            // Where this school sits in its group. Null for a standalone
            // school, which is what most are. See docs/branches.md.
            'parent_school_id' => $this->parent_school_id,
            'parent_school_name' => $this->whenLoaded('parent', fn () => $this->parent?->name),
            'branch_count' => $this->whenCounted('branches'),
            'registration_number' => $this->registration_number,
            'email' => $this->email,
            'phone' => $this->phone,
            'address' => $this->address,
            'city' => $this->city,
            'state' => $this->state,
            'country' => $this->country,
            'postal_code' => $this->postal_code,
            'latitude' => $this->latitude === null ? null : (string) $this->latitude,
            'longitude' => $this->longitude === null ? null : (string) $this->longitude,
            'currency_code' => $this->currency_code,
            'timezone' => $this->timezone,
            'logo_url' => $this->logo_url,
            'status' => $this->status->value,
            'created_at' => $this->created_at,
        ];
    }
}
