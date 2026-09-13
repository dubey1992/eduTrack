@php
    $money = fn ($value) => $payment->currency_code . ' ' . number_format((float) $value, 2);
    $remaining = $payment->remainingAmount();
@endphp
<x-mail::message>
# Payment receipt {{ $receiptNumber }}

A payment has been recorded for **{{ $payment->school?->name }}**.

<x-mail::table>
| | |
|:---|---:|
| {{ $payment->payment_type->label() }} | {{ $money($payment->amount) }} |
| Received | {{ $money($payment->paid_amount) }} |
| **{{ $payment->status === \App\Enums\PaymentStatus::Paid ? 'Balance' : 'Balance due' }}** | **{{ $money($remaining) }}** |
</x-mail::table>

@if ($payment->status === \App\Enums\PaymentStatus::Partial)
This payment is **partly paid**. {{ $money($remaining) }} is still outstanding.
@elseif ($payment->status === \App\Enums\PaymentStatus::Paid)
This payment is **settled in full**. Thank you.
@elseif ($payment->status === \App\Enums\PaymentStatus::Cancelled)
This payment has been **cancelled**. Nothing is owed against it.
@else
This payment is **awaiting payment**.
@endif

The full receipt is attached as a PDF.

Thanks,<br>
{{ config('app.name') }}
</x-mail::message>
