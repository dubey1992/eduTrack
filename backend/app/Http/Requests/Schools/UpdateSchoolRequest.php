<?php

namespace App\Http\Requests\Schools;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateSchoolRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('school'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $schoolId = $this->route('school')->id;

        return [
            'name' => ['sometimes', 'required', 'string', 'max:255'],
            'registration_number' => ['nullable', 'string', 'max:100'],
            'email' => ['sometimes', 'required', 'email', Rule::unique('schools', 'email')->ignore($schoolId)],
            'phone' => ['sometimes', 'required', 'string', 'max:20'],
            'address' => ['sometimes', 'required', 'string', 'max:255'],
            'city' => ['sometimes', 'required', 'string', 'max:100'],
            'state' => ['sometimes', 'required', 'string', 'max:100'],
            'country' => ['sometimes', 'required', 'string', 'max:100'],
            'postal_code' => ['sometimes', 'required', 'string', 'max:20'],
            'currency_code' => ['sometimes', 'required', 'string', 'regex:/^[A-Z]{3}$/'],
            'logo_url' => ['nullable', 'url', 'max:2048'],
        ];
    }
}
