<?php

namespace App\Services;

use App\Enums\PaymentStatus;
use App\Jobs\SendPaymentReceiptJob;
use App\Models\Payment;
use App\Models\School;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolClock;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class PaymentService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(array $filters): LengthAwarePaginator
    {
        return Payment::query()
            ->with(['school', 'creator'])
            ->when($filters['school_id'] ?? null, fn ($query, $schoolId) => $query->where('school_id', $schoolId))
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            ->when(
                $filters['payment_type'] ?? null,
                fn ($query, $type) => $query->where('payment_type', $type)
            )
            ->orderByDesc('payment_date')
            ->orderByDesc('id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Payment
    {
        $school = School::findOrFail($data['school_id']);
        $amount = (float) $data['amount'];
        $paid = $this->paidAmountFor($data, $amount);

        $payment = Payment::create([
            ...$data,
            'paid_amount' => $paid,
            // Derived from the figures rather than taken at face value, so a
            // payment can never read "Paid" with a balance outstanding.
            'status' => Payment::statusFor($amount, $paid, $this->requestedStatus($data)),
            // Never trusted from the client - always the owning school's
            // currency at the moment of payment (CLAUDE.md rule 5).
            'currency_code' => $school->currency_code,
            'created_by' => $actor->id,
        ]);

        $this->sendReceipt($payment);

        return $payment;
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(Payment $payment, array $data): Payment
    {
        $amount = (float) ($data['amount'] ?? $payment->amount);
        $paid = $this->paidAmountFor($data, $amount, (float) $payment->paid_amount);

        $before = [(string) $payment->amount, (string) $payment->paid_amount, $payment->status];

        $payment->update([
            ...$data,
            'paid_amount' => $paid,
            'status' => Payment::statusFor($amount, $paid, $this->requestedStatus($data)),
        ]);

        $after = [(string) $payment->amount, (string) $payment->paid_amount, $payment->status];

        // Only when the money or the standing changed. Re-sending a receipt
        // because somebody corrected a reference number would be noise.
        if ($before !== $after) {
            $this->sendReceipt($payment);
        }

        return $payment;
    }

    /**
     * Emails the school's admins a receipt, on the queue so recording a
     * payment never waits for it.
     */
    public function sendReceipt(Payment $payment): void
    {
        DB::afterCommit(fn () => SendPaymentReceiptJob::dispatch($payment->id));
    }

    /**
     * What was actually received.
     *
     * When the client sends no figure, the status it asked for says what it
     * meant: "Paid" means all of it, "Pending" means none of it yet. That
     * keeps the plain "just mark it paid" path working without forcing every
     * caller to restate the amount twice.
     *
     * Never more than the agreed amount, so lowering the amount on an
     * existing payment cannot leave more paid than is owed.
     *
     * @param  array<string, mixed>  $data
     */
    private function paidAmountFor(array $data, float $amount, float $fallback = 0.0): float
    {
        if (array_key_exists('paid_amount', $data) && $data['paid_amount'] !== null) {
            return min((float) $data['paid_amount'], $amount);
        }

        return match ($this->requestedStatus($data)) {
            PaymentStatus::Paid => $amount,
            PaymentStatus::Pending, PaymentStatus::Cancelled => 0.0,
            default => min($fallback, $amount),
        };
    }

    /**
     * @param  array<string, mixed>  $data
     */
    private function requestedStatus(array $data): ?PaymentStatus
    {
        $status = $data['status'] ?? null;

        if ($status === null) {
            return null;
        }

        return $status instanceof PaymentStatus ? $status : PaymentStatus::from($status);
    }

    /**
     * Collection totals for the payment dashboard. Every figure is grouped
     * by currency and never summed across currencies - CLAUDE.md rule 5
     * forbids a single blended total since this isn't a forex system.
     *
     * @return array{
     *     total_by_currency: array<int, array{currency_code: string, total: string}>,
     *     monthly_by_currency: array<int, array{currency_code: string, total: string}>,
     *     pending_by_currency: array<int, array{currency_code: string, total: string}>,
     *     pending_count: int,
     * }
     */
    public function collectionSummary(): array
    {
        $platformNow = SchoolClock::platform()->now();

        // Collected means money that actually arrived, so it sums
        // paid_amount and counts a part-payment for the part that was paid.
        // Summing `amount` over settled rows only would miss those entirely.
        $collected = fn () => Payment::query()
            ->whereNot('status', PaymentStatus::Cancelled)
            ->select('currency_code', DB::raw('SUM(paid_amount) as total'))
            ->groupBy('currency_code')
            ->havingRaw('SUM(paid_amount) > 0');

        $totalByCurrency = $collected()->get();

        $monthlyByCurrency = $collected()
            // Cross-school totals belong to no single school, so "this month"
            // is the platform's month - see config('app.platform_timezone').
            ->whereYear('payment_date', $platformNow->year)
            ->whereMonth('payment_date', $platformNow->month)
            ->get();

        // Outstanding is what is still owed, which includes the unpaid part
        // of a partial payment - not only the rows nobody has paid at all.
        $outstandingScope = fn () => Payment::query()
            ->whereIn('status', [PaymentStatus::Pending, PaymentStatus::Partial]);

        $outstandingByCurrency = $outstandingScope()
            ->select('currency_code', DB::raw('SUM(amount - paid_amount) as total'))
            ->groupBy('currency_code')
            ->havingRaw('SUM(amount - paid_amount) > 0')
            ->get();

        return [
            'total_by_currency' => $totalByCurrency->toArray(),
            'monthly_by_currency' => $monthlyByCurrency->toArray(),
            'pending_by_currency' => $outstandingByCurrency->toArray(),
            'pending_count' => $outstandingScope()->count(),
        ];
    }
}
