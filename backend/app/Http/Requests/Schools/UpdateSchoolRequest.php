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
    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'latitude.required_with' => 'Enter a latitude as well, or clear the longitude.',
            'longitude.required_with' => 'Enter a longitude as well, or clear the latitude.',
            'latitude.between' => 'A latitude is between -90 and 90.',
            'longitude.between' => 'A longitude is between -180 and 180.',
        ];
    }

    public function rules(): array
    {
        $schoolId = $this->route('school')->id;

        return [
            'name' => ['sometimes', 'required', 'string', 'max:255'],
            'registration_number' => ['nullable', 'string', 'max:100'],
            'email' => ['sometimes', 'required', 'email', Rule::unique('schools', 'email')->ignore($schoolId)],
            'phone' => ['sometimes', 'required', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'address' => ['sometimes', 'required', 'string', 'max:255'],
            'city' => ['sometimes', 'required', 'string', 'max:100'],
            'state' => ['sometimes', 'required', 'string', 'max:100'],
            'country' => ['sometimes', 'required', 'string', 'max:100'],
            'postal_code' => ['sometimes', 'required', 'string', 'max:20'],
            // A coordinate is optional - most schools are onboarded without
            // one - but if either is given both must be, since half a
            // coordinate points nowhere.
            'latitude' => ['nullable', 'numeric', 'between:-90,90', 'required_with:longitude'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180', 'required_with:latitude'],
            'currency_code' => ['sometimes', 'required', 'string', 'regex:/^[A-Z]{3}$/'],
            'timezone' => ['sometimes', 'required', 'string', 'timezone:all'],
            'logo_url' => ['nullable', 'url', 'max:2048'],
        ];
    }
}
