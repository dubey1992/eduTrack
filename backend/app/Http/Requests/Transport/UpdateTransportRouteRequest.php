<?php

namespace App\Http\Requests\Transport;

use App\Enums\TransportStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class UpdateTransportRouteRequest extends FormRequest
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
        $route = $this->route('route');

        return [
            'name' => [
                'sometimes', 'required', 'string', 'max:100',
                Rule::unique('transport_routes', 'name')
                    ->where(fn ($query) => $query->where('school_id', $route->school_id))
                    ->ignore($route->id),
            ],
            // Keeping the vehicle/driver the route already has must stay
            // valid even if that record has since been deactivated, so the
            // "active" requirement only applies to a NEW choice.
            'vehicle_id' => [
                'nullable', 'integer',
                Rule::exists('vehicles', 'id')->where(fn ($query) => $query
                    ->where('school_id', $route->school_id)
                    ->where(fn ($query) => $query
                        ->where('status', TransportStatus::Active->value)
                        ->orWhere('id', $route->vehicle_id))),
                Rule::unique('transport_routes', 'vehicle_id')->ignore($route->id),
            ],
            'driver_id' => [
                'nullable', 'integer',
                Rule::exists('drivers', 'id')->where(fn ($query) => $query
                    ->where('school_id', $route->school_id)
                    ->where(fn ($query) => $query
                        ->where('status', TransportStatus::Active->value)
                        ->orWhere('id', $route->driver_id))),
                Rule::unique('transport_routes', 'driver_id')->ignore($route->id),
            ],
            'status' => ['sometimes', 'required', new Enum(TransportStatus::class)],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'vehicle_id.exists' => 'The selected vehicle is not an active vehicle of this school.',
            'vehicle_id.unique' => 'That vehicle is already serving another route.',
            'driver_id.exists' => 'The selected driver is not an active driver of this school.',
            'driver_id.unique' => 'That driver is already assigned to another route.',
        ];
    }
}
