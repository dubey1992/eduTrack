<?php

namespace App\Http\Requests\Transport;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateTransportStopRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('stop')->route);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $stop = $this->route('stop');

        return [
            'name' => [
                'sometimes', 'required', 'string', 'max:100',
                Rule::unique('transport_stops', 'name')
                    ->where(fn ($query) => $query->where('route_id', $stop->route_id))
                    ->ignore($stop->id),
            ],
            'sequence_number' => [
                'sometimes', 'required', 'integer', 'min:1', 'max:200',
                Rule::unique('transport_stops', 'sequence_number')
                    ->where(fn ($query) => $query->where('route_id', $stop->route_id))
                    ->ignore($stop->id),
            ],
            'pickup_time' => ['nullable', 'date_format:H:i'],
            'drop_time' => ['nullable', 'date_format:H:i'],
        ];
    }
}
