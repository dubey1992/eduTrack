<?php

namespace App\Http\Requests\Transport;

use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\Vehicle;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreVehicleRequest extends FormRequest
{
    use ScopesSchool;

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
            'school_id' => $this->schoolIdRules(),
            'name' => ['required', 'string', 'max:50'],
            'registration_number' => [
                'required', 'string', 'max:30',
                Rule::unique('vehicles', 'registration_number')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'capacity' => ['required', 'integer', 'min:1', 'max:200'],
        ];
    }
}
