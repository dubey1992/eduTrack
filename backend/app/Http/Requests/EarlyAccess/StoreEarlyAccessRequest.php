<?php

namespace App\Http\Requests\EarlyAccess;

use Illuminate\Foundation\Http\FormRequest;

/**
 * The form on the marketing page. Reachable without an account - it is how a
 * school that has none asks for one - so everything here is validated as if
 * it came from a stranger, because it did.
 */
class StoreEarlyAccessRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'school_name' => ['required', 'string', 'max:150'],
            'contact_name' => ['required', 'string', 'max:150'],
            'contact_role' => ['nullable', 'string', 'max:100'],
            'email' => ['required', 'email', 'max:255'],
            // Multi-nation from the first contact - e.g. "+91 9876543210".
            'phone' => ['required', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'city' => ['required', 'string', 'max:100'],
            'country' => ['required', 'string', 'max:100'],
            // Roughly how big they are, which is the single most useful thing
            // for deciding who to call first. Optional: plenty of people do
            // not know, and demanding it loses the lead.
            'expected_students' => ['nullable', 'integer', 'min:1', 'max:200000'],
            'current_software' => ['nullable', 'string', 'max:150'],
            'message' => ['nullable', 'string', 'max:2000'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'phone.regex' => 'Include the country code, like +91 9876543210.',
            'expected_students.max' => 'That is more students than any school we know of - please get in touch directly.',
        ];
    }
}
