<?php

namespace App\Http\Resources;

use App\Models\User;
use App\Support\SchoolClock;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin User
 */
class UserResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        // Reads the already-eager-loaded school where there is one, so a
        // paginated user list does not fire a query per row.
        $clock = $this->relationLoaded('school')
            ? SchoolClock::for($this->school)
            : SchoolClock::forUser($this->resource);

        return [
            'id' => $this->id,
            'first_name' => $this->first_name,
            'last_name' => $this->last_name,
            'name' => $this->name,
            'email' => $this->email,
            'mobile' => $this->mobile,
            'role' => $this->role->value,
            'is_sub_admin' => $this->is_sub_admin,
            'status' => $this->status->value,
            'school_id' => $this->school_id,
            // True for an account created by a bulk import, which was given
            // a generated password: the client keeps it on the
            // change-password screen until it chooses one of its own.
            'must_change_password' => $this->must_change_password,
            'school_name' => $this->whenLoaded('school', fn () => $this->school?->name),
            // The session's clock. The client measures every date it shows or
            // defaults to against these two, never against the browser's own
            // timezone. A Super Admin belongs to no school and gets the
            // platform's zone.
            'timezone' => $clock->timezone(),
            'current_time' => $clock->now()->toIso8601String(),
        ];
    }
}
