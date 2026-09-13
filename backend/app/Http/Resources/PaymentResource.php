<?php

namespace App\Http\Resources;

use App\Models\Payment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Payment
 */
class PaymentResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'school_name' => $this->whenLoaded('school', fn () => $this->school->name),
            'payment_type' => $this->payment_type->value,
            'amount' => (string) $this->amount,
            // What arrived, and what is still owed. The balance is computed
            // here rather than stored, so it cannot drift from the figures
            // it describes.
            'paid_amount' => (string) $this->paid_amount,
            'remaining_amount' => $this->remainingAmount(),
            'currency_code' => $this->currency_code,
            'payment_date' => $this->payment_date->toDateString(),
            'payment_mode' => $this->payment_mode->value,
            'reference_number' => $this->reference_number,
            'notes' => $this->notes,
            'status' => $this->status->value,
            'created_by' => $this->created_by,
            'created_by_name' => $this->whenLoaded('creator', fn () => $this->creator->name),
            'receipt_sent_at' => $this->receipt_sent_at,
            'created_at' => $this->created_at,
        ];
    }
}
