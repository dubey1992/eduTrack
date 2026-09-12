<?php

namespace App\Http\Requests\Communication;

use App\Enums\MessageCategory;
use App\Enums\MessageChannel;
use App\Enums\MessageStatus;
use App\Models\Message;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rules\Enum;

class MessageIndexRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('viewAny', Message::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'school_id' => ['nullable', 'integer', 'exists:schools,id'],
            'category' => ['nullable', new Enum(MessageCategory::class)],
            'channel' => ['nullable', new Enum(MessageChannel::class)],
            'status' => ['nullable', new Enum(MessageStatus::class)],
            'date_from' => ['nullable', 'date'],
            'date_to' => ['nullable', 'date', 'after_or_equal:date_from'],
            'q' => ['nullable', 'string', 'max:100'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ];
    }
}
