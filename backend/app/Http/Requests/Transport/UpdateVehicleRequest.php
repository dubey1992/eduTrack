<?php

namespace App\Http\Requests\Transport;

use App\Enums\TransportStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class UpdateVehicleRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('vehicle'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $vehicle = $this->route('vehicle');

        return [
            'name' => ['sometimes', 'required', 'string', 'max:50'],
            'registration_number' => [
                'sometimes', 'required', 'string', 'max:30',
                Rule::unique('vehicles', 'registration_number')
                    ->where(fn ($query) => $query->where('school_id', $vehicle->school_id))
                    ->ignore($vehicle->id),
            ],
            'capacity' => ['sometimes', 'required', 'integer', 'min:1', 'max:200'],
            'status' => ['sometimes', 'required', new Enum(TransportStatus::class)],
        ];
    }
}
