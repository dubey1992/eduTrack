<?php

namespace App\Http\Requests\Payments;

use App\Enums\PaymentMode;
use App\Enums\PaymentStatus;
use App\Enums\PaymentType;
use App\Models\Payment;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rules\Enum;

class StorePaymentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Payment::class);
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
            'paid_amount.lte' => 'The amount received cannot be more than the payment amount.',
        ];
    }

    public function rules(): array
    {
        return [
            'school_id' => ['required', 'integer', 'exists:schools,id'],
            'payment_type' => ['required', new Enum(PaymentType::class)],
            // Matches the amount column's DECIMAL(12,2) shape (CLAUDE.md
            // rule 5) - without this, a value like "12.345" would pass
            // `numeric` and only get silently rounded by MySQL.
            'amount' => ['required', 'numeric', 'min:0.01', 'regex:/^\d+(\.\d{1,2})?$/'],
            'payment_date' => ['required', 'date'],
            'payment_mode' => ['required', new Enum(PaymentMode::class)],
            'reference_number' => ['nullable', 'string', 'max:100'],
            'notes' => ['nullable', 'string', 'max:1000'],
            // How much has actually arrived. The status is derived from it
            // (see Payment::statusFor), so the two can never contradict each
            // other; 'status' is still accepted because Cancelled is a
            // decision rather than a consequence of the figures.
            'paid_amount' => [
                'nullable', 'numeric', 'min:0', 'regex:/^\d+(\.\d{1,2})?$/',
                'lte:amount',
            ],
            'status' => ['required', new Enum(PaymentStatus::class)],
        ];
    }
}
