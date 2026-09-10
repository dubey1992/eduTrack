<?php

namespace App\Http\Requests\Transport;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreTransportStopRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('route'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $routeId = $this->route('route')->id;

        return [
            'name' => [
                'required', 'string', 'max:100',
                Rule::unique('transport_stops', 'name')->where(fn ($query) => $query->where('route_id', $routeId)),
            ],
            'sequence_number' => [
                'required', 'integer', 'min:1', 'max:200',
                Rule::unique('transport_stops', 'sequence_number')->where(fn ($query) => $query->where('route_id', $routeId)),
            ],
            'pickup_time' => ['nullable', 'date_format:H:i'],
            'drop_time' => ['nullable', 'date_format:H:i'],
        ];
    }
}
