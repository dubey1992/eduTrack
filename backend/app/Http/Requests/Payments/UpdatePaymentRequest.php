<?php

namespace App\Http\Requests\Payments;

use App\Enums\PaymentMode;
use App\Enums\PaymentStatus;
use App\Enums\PaymentType;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rules\Enum;

class UpdatePaymentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('payment'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // school_id and currency_code are fixed at creation - not
            // editable here (see PaymentService::create).
            'payment_type' => ['sometimes', 'required', new Enum(PaymentType::class)],
            'amount' => ['sometimes', 'required', 'numeric', 'min:0.01', 'regex:/^\d+(\.\d{1,2})?$/'],
            'payment_date' => ['sometimes', 'required', 'date'],
            'payment_mode' => ['sometimes', 'required', new Enum(PaymentMode::class)],
            'reference_number' => ['nullable', 'string', 'max:100'],
            'notes' => ['nullable', 'string', 'max:1000'],
            'status' => ['sometimes', 'required', new Enum(PaymentStatus::class)],
        ];
    }
}
