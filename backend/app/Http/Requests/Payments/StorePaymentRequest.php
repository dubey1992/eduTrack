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
            'status' => ['required', new Enum(PaymentStatus::class)],
        ];
    }
}
