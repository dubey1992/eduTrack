<?php

namespace App\Http\Requests\Transport;

use App\Enums\TransportStatus;
use App\Enums\UserRole;
use App\Models\TransportRoute;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreTransportRouteRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', TransportRoute::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'school_id' => $this->user()->role === UserRole::SuperAdmin
                ? ['required', 'integer', 'exists:schools,id']
                : ['nullable'],
            'name' => [
                'required', 'string', 'max:100',
                Rule::unique('transport_routes', 'name')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'vehicle_id' => [
                'nullable', 'integer',
                Rule::exists('vehicles', 'id')->where(fn ($query) => $query
                    ->where('school_id', $this->resolvedSchoolId())
                    ->where('status', TransportStatus::Active->value)),
                Rule::unique('transport_routes', 'vehicle_id'),
            ],
            'driver_id' => [
                'nullable', 'integer',
                Rule::exists('drivers', 'id')->where(fn ($query) => $query
                    ->where('school_id', $this->resolvedSchoolId())
                    ->where('status', TransportStatus::Active->value)),
                Rule::unique('transport_routes', 'driver_id'),
            ],
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

    private function resolvedSchoolId(): ?int
    {
        return $this->user()->role === UserRole::SuperAdmin
            ? $this->integer('school_id')
            : $this->user()->school_id;
    }
}
