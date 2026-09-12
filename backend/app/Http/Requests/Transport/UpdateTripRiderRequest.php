<?php

namespace App\Http\Requests\Transport;

use App\Enums\TripRiderStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateTripRiderRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('manage', $this->route('trip'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // "pending" is the starting state, never something you set.
            'status' => ['required', Rule::in([
                TripRiderStatus::Boarded->value, TripRiderStatus::Dropped->value, TripRiderStatus::Absent->value,
            ])],
        ];
    }
}
