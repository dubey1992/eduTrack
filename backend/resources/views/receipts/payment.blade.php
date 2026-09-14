{{-- The PDF receipt emailed to a school's admins. Rendered by dompdf, which
     supports only simple CSS - hence tables for layout and no flexbox. --}}
@php
    $isSettled = $payment->status === \App\Enums\PaymentStatus::Paid;
    $isCancelled = $payment->status === \App\Enums\PaymentStatus::Cancelled;
    $remaining = $payment->remainingAmount();
    $money = fn ($value) => $payment->currency_code . ' ' . number_format((float) $value, 2);
@endphp
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{{ $receiptNumber }}</title>
    <style>
        body { font-family: DejaVu Sans, sans-serif; font-size: 12px; color: #1f2430; margin: 0; }
        .sheet { padding: 36px 40px; }
        .head { border-bottom: 2px solid #1f2430; padding-bottom: 14px; }
        .brand { font-size: 20px; font-weight: bold; }
        .muted { color: #6b7280; }
        .right { text-align: right; }
        h1 { font-size: 16px; margin: 22px 0 10px; }
        table { width: 100%; border-collapse: collapse; }
        .meta td { padding: 4px 0; vertical-align: top; }
        .meta .key { color: #6b7280; width: 130px; }
        .amounts { margin-top: 8px; border: 1px solid #d7dbe3; }
        .amounts td { padding: 9px 12px; border-bottom: 1px solid #eceef2; }
        .amounts tr:last-child td { border-bottom: 0; }
        .amounts .label { color: #4b5563; }
        .amounts .value { text-align: right; font-weight: bold; }
        .due td { background: #fdecec; color: #8a1c1c; }
        .settled td { background: #eaf7ee; color: #155e2e; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 10px; font-weight: bold; font-size: 11px; }
        .badge-paid { background: #eaf7ee; color: #155e2e; }
        .badge-part { background: #fff4e5; color: #8a5300; }
        .badge-pending { background: #fdecec; color: #8a1c1c; }
        .badge-cancelled { background: #eceef2; color: #4b5563; }
        .note { margin-top: 26px; padding-top: 12px; border-top: 1px solid #eceef2; font-size: 11px; }
    </style>
</head>
<body>
<div class="sheet">
    <table class="head">
        <tr>
            <td>
                <div class="brand">{{ config('app.name') }}</div>
                <div class="muted">Payment receipt</div>
            </td>
            <td class="right">
                <div><strong>{{ $receiptNumber }}</strong></div>
                <div class="muted">Issued {{ $issuedOn }}</div>
            </td>
        </tr>
    </table>

    <h1>Billed to</h1>
    <table class="meta">
        <tr><td class="key">School</td><td>{{ $payment->school?->name ?? '-' }}</td></tr>
        @if ($payment->school?->address)
            <tr>
                <td class="key">Address</td>
                <td>{{ $payment->school->address }}, {{ $payment->school->city }}, {{ $payment->school->country }}</td>
            </tr>
        @endif
        <tr><td class="key">Email</td><td>{{ $payment->school?->email ?? '-' }}</td></tr>
    </table>

    <h1>Payment</h1>
    <table class="meta">
        <tr><td class="key">For</td><td>{{ $payment->payment_type->label() }}</td></tr>
        <tr><td class="key">Date</td><td>{{ $payment->payment_date->format(\App\Support\DateFormats::DATE) }}</td></tr>
        <tr><td class="key">Method</td><td>{{ $payment->payment_mode->label() }}</td></tr>
        @if ($payment->reference_number)
            <tr><td class="key">Reference</td><td>{{ $payment->reference_number }}</td></tr>
        @endif
        <tr>
            <td class="key">Status</td>
            <td>
                <span class="badge badge-{{ ['paid' => 'paid', 'partial' => 'part', 'pending' => 'pending', 'cancelled' => 'cancelled'][$payment->status->value] }}">
                    {{ $payment->status->label() }}
                </span>
            </td>
        </tr>
    </table>

    <table class="amounts">
        <tr>
            <td class="label">Amount</td>
            <td class="value">{{ $money($payment->amount) }}</td>
        </tr>
        <tr>
            <td class="label">Amount received</td>
            <td class="value">{{ $money($payment->paid_amount) }}</td>
        </tr>
        {{-- The line that makes a part-payment honest: it says plainly what
             is still owed, rather than leaving the reader to subtract. --}}
        <tr class="{{ $isSettled || $isCancelled ? 'settled' : 'due' }}">
            <td class="label">{{ $isCancelled ? 'Cancelled' : ($isSettled ? 'Balance' : 'Balance due') }}</td>
            <td class="value">{{ $money($remaining) }}</td>
        </tr>
    </table>

    @if ($payment->notes)
        <h1>Notes</h1>
        <div>{{ $payment->notes }}</div>
    @endif

    <div class="note muted">
        @if ($isCancelled)
            This payment has been cancelled. Nothing is owed against it.
        @elseif ($isSettled)
            Paid in full. Thank you.
        @else
            {{ $money($remaining) }} remains outstanding on this payment.
        @endif
        <br>
        Recorded by {{ $payment->creator?->name ?? 'the platform team' }}.
        This receipt is issued electronically and is valid without a signature.
    </div>
</div>
</body>
</html>
