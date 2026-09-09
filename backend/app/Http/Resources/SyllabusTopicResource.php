<?php

namespace App\Http\Resources;

use App\Models\SyllabusTopic;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin SyllabusTopic
 */
class SyllabusTopicResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'subject_id' => $this->subject_id,
            'subject_name' => $this->whenLoaded('subject', fn () => $this->subject?->name),
            'title' => $this->title,
            'sequence_number' => $this->sequence_number,
        ];
    }
}
