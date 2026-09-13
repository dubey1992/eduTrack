<?php

namespace App\Models;

use App\Enums\PaymentMode;
use App\Enums\PaymentStatus;
use App\Enums\PaymentType;
use Database\Factories\PaymentFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'school_id', 'payment_type', 'amount', 'paid_amount', 'currency_code',
    'payment_date', 'payment_mode', 'reference_number', 'notes', 'status',
    'receipt_sent_at', 'created_by',
])]
class Payment extends Model
{
    /** @use HasFactory<PaymentFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'payment_type' => PaymentType::class,
            'payment_mode' => PaymentMode::class,
            'status' => PaymentStatus::class,
            'payment_date' => 'date',
            'amount' => 'decimal:2',
            'paid_amount' => 'decimal:2',
            'receipt_sent_at' => 'datetime',
        ];
    }

    /**
     * What is still owed on this payment.
     *
     * Derived, never stored - a remaining balance kept in its own column is
     * one that can drift out of step with the two figures it comes from.
     * A cancelled payment owes nothing.
     */
    public function remainingAmount(): string
    {
        if ($this->status === PaymentStatus::Cancelled) {
            return '0.00';
        }

        return number_format(max(0, (float) $this->amount - (float) $this->paid_amount), 2, '.', '');
    }

    public function isFullySettled(): bool
    {
        return (float) $this->paid_amount >= (float) $this->amount;
    }

    /**
     * The status these figures describe.
     *
     * Cancelled is the one status a person chooses; the rest follow from the
     * money, so a row can never read "Paid" with a balance outstanding.
     */
    public static function statusFor(float $amount, float $paidAmount, ?PaymentStatus $requested = null): PaymentStatus
    {
        if ($requested === PaymentStatus::Cancelled) {
            return PaymentStatus::Cancelled;
        }

        return match (true) {
            $paidAmount <= 0 => PaymentStatus::Pending,
            $paidAmount >= $amount => PaymentStatus::Paid,
            default => PaymentStatus::Partial,
        };
    }

    /**
     * @return BelongsTo<School, $this>
     */
    public function school(): BelongsTo
    {
        return $this->belongsTo(School::class);
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
