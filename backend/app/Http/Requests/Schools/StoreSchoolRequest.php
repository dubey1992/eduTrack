<?php

namespace App\Http\Requests\Schools;

use App\Models\School;
use App\Rules\ValidParentSchool;
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
        return [
            // A branch of an existing school. Null for a standalone school,
            // which is what most are. See docs/branches.md.
            'parent_school_id' => ['nullable', 'integer', 'exists:schools,id', new ValidParentSchool],
            // Set when this school is being onboarded from a signup request,
            // so the request can record what it became. See docs/early-access.md.
            'early_access_request_id' => ['nullable', 'integer', 'exists:early_access_requests,id'],
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
            // A coordinate is optional - most schools are onboarded without
            // one - but if either is given both must be, since half a
            // coordinate points nowhere.
            'latitude' => ['nullable', 'numeric', 'between:-90,90', 'required_with:longitude'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180', 'required_with:latitude'],
            'currency_code' => ['required', 'string', 'regex:/^[A-Z]{3}$/'],
            // An IANA name such as Asia/Kolkata. This decides what "today"
            // means for everything the school records.
            'timezone' => ['required', 'string', 'timezone:all'],
            'logo_url' => ['nullable', 'url', 'max:2048'],
        ];
    }
}
