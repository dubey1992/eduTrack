<?php

namespace App\Http\Requests\Transport;

use App\Enums\UserRole;
use App\Models\Vehicle;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreVehicleRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Vehicle::class);
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
            'name' => ['required', 'string', 'max:50'],
            'registration_number' => [
                'required', 'string', 'max:30',
                Rule::unique('vehicles', 'registration_number')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'capacity' => ['required', 'integer', 'min:1', 'max:200'],
        ];
    }

    private function resolvedSchoolId(): ?int
    {
        return $this->user()->role === UserRole::SuperAdmin
            ? $this->integer('school_id')
            : $this->user()->school_id;
    }
}
