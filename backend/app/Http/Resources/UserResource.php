<?php

namespace App\Http\Resources;

use App\Models\User;
use App\Support\SchoolClock;
use App\Support\SchoolScope;
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
            // Whether "my school" is ambiguous for this account, so the
            // client knows to ask which branch a record belongs to. True for
            // an admin of a school in a group, false for a standalone one -
            // which is why the client cannot work it out from the role alone.
            //
            // Only ever computed for the signed-in user reading their own
            // session: it costs a query, and a paginated user list would pay
            // it per row for something no row needs.
            'manages_branches' => $this->when(
                $request->user()?->getKey() === $this->getKey(),
                fn () => SchoolScope::for($this->resource)->coversAGroup(),
            ),
            // The session's clock. The client measures every date it shows or
            // defaults to against these two, never against the browser's own
            // timezone. A Super Admin belongs to no school and gets the
            // platform's zone.
            'timezone' => $clock->timezone(),
            'current_time' => $clock->now()->toIso8601String(),
        ];
    }
}
