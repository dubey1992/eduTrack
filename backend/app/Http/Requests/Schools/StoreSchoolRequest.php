<?php

namespace App\Http\Requests\Schools;

use App\Models\School;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreSchoolRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', School::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:255'],
            'registration_number' => ['nullable', 'string', 'max:100'],
            'email' => ['required', 'email', Rule::unique('schools', 'email')],
            // Multi-nation schools always carry a dial code - e.g. "+91 9876543210".
            'phone' => ['required', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'address' => ['required', 'string', 'max:255'],
            'city' => ['required', 'string', 'max:100'],
            'state' => ['required', 'string', 'max:100'],
            'country' => ['required', 'string', 'max:100'],
            'postal_code' => ['required', 'string', 'max:20'],
            'currency_code' => ['required', 'string', 'regex:/^[A-Z]{3}$/'],
            // An IANA name such as Asia/Kolkata. This decides what "today"
            // means for everything the school records.
            'timezone' => ['required', 'string', 'timezone:all'],
            'logo_url' => ['nullable', 'url', 'max:2048'],
        ];
    }
}
