<?php

namespace App\Http\Requests\EarlyAccess;

use App\Enums\EarlyAccessStatus;
use App\Models\EarlyAccessRequest;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class ReviewEarlyAccessRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('review', $this->route('earlyAccessRequest') ?? EarlyAccessRequest::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // Converted is deliberately not settable: it means a school
            // exists, and the system sets it when one does.
            'status' => ['sometimes', 'required', Rule::in(EarlyAccessStatus::settable())],
            'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'status.in' => 'A request becomes Converted by onboarding the school, not by saying so.',
        ];
    }
}
