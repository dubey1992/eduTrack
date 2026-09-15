<?php

namespace App\Http\Resources;

use App\Models\EarlyAccessRequest;
use App\Support\DateFormats;
use App\Support\SchoolClock;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin EarlyAccessRequest
 */
class EarlyAccessRequestResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        // A request belongs to no school, so there is no school clock to read
        // it by - the platform's is the only honest one.
        $clock = SchoolClock::platform();

        return [
            'id' => $this->id,
            'school_name' => $this->school_name,
            'contact_name' => $this->contact_name,
            'contact_role' => $this->contact_role,
            'email' => $this->email,
            'phone' => $this->phone,
            'city' => $this->city,
            'country' => $this->country,
            'expected_students' => $this->expected_students,
            'current_software' => $this->current_software,
            'message' => $this->message,
            'status' => $this->status->value,
            'status_label' => $this->status->label(),
            'notes' => $this->notes,
            'converted_school_id' => $this->converted_school_id,
            'converted_school_name' => $this->whenLoaded('convertedSchool', fn () => $this->convertedSchool?->name),
            'reviewed_by_name' => $this->whenLoaded('reviewedBy', fn () => $this->reviewedBy?->name),
            'reviewed_at' => $clock->format($this->reviewed_at, DateFormats::DATE_TIME),
            'submitted_at' => $clock->format($this->created_at, DateFormats::DATE_TIME),
        ];
    }
}
