<?php

namespace App\Services;

use App\Enums\PaymentStatus;
use App\Models\Payment;
use App\Models\School;
use App\Models\User;
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
            ->paginate(perPage: 20);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Payment
    {
        $school = School::findOrFail($data['school_id']);

        return Payment::create([
            ...$data,
            // Never trusted from the client - always the owning school's
            // currency at the moment of payment (CLAUDE.md rule 5).
            'currency_code' => $school->currency_code,
            'created_by' => $actor->id,
        ]);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(Payment $payment, array $data): Payment
    {
        $payment->update($data);

        return $payment;
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
        $totalByCurrency = Payment::query()
            ->where('status', PaymentStatus::Paid)
            ->select('currency_code', DB::raw('SUM(amount) as total'))
            ->groupBy('currency_code')
            ->get();

        $monthlyByCurrency = Payment::query()
            ->where('status', PaymentStatus::Paid)
            ->whereYear('payment_date', now()->year)
            ->whereMonth('payment_date', now()->month)
            ->select('currency_code', DB::raw('SUM(amount) as total'))
            ->groupBy('currency_code')
            ->get();

        $pendingByCurrency = Payment::query()
            ->where('status', PaymentStatus::Pending)
            ->select('currency_code', DB::raw('SUM(amount) as total'))
            ->groupBy('currency_code')
            ->get();

        return [
            'total_by_currency' => $totalByCurrency->toArray(),
            'monthly_by_currency' => $monthlyByCurrency->toArray(),
            'pending_by_currency' => $pendingByCurrency->toArray(),
            'pending_count' => Payment::query()->where('status', PaymentStatus::Pending)->count(),
        ];
    }
}
