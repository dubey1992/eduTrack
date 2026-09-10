<?php

namespace App\Http\Requests\Transport;

use App\Enums\TransportStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class UpdateDriverRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('driver'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $driver = $this->route('driver');

        return [
            'name' => ['sometimes', 'required', 'string', 'max:150'],
            'mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'licence_number' => [
                'sometimes', 'required', 'string', 'max:50',
                Rule::unique('drivers', 'licence_number')
                    ->where(fn ($query) => $query->where('school_id', $driver->school_id))
                    ->ignore($driver->id),
            ],
            'licence_expiry' => ['nullable', 'date'],
            'status' => ['sometimes', 'required', new Enum(TransportStatus::class)],
        ];
    }
}
