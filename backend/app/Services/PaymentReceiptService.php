<?php

namespace App\Services;

use App\Models\Payment;
use App\Support\DateFormats;
use Barryvdh\DomPDF\Facade\Pdf;

/**
 * Renders the PDF receipt for a payment.
 *
 * The receipt states what was agreed, what has been received and what is
 * still owed, so a part-payment produces an honest document rather than one
 * that reads as though the account is settled.
 */
class PaymentReceiptService
{
    /**
     * "RCPT-000042" - stable for a payment, so a school re-sent the same
     * receipt files it over the one it already has rather than beside it.
     */
    public function receiptNumber(Payment $payment): string
    {
        return 'RCPT-'.str_pad((string) $payment->id, 6, '0', STR_PAD_LEFT);
    }

    public function fileName(Payment $payment): string
    {
        return $this->receiptNumber($payment).'.pdf';
    }

    /**
     * The rendered PDF as a string, ready to attach to an email.
     */
    public function render(Payment $payment): string
    {
        $payment->loadMissing(['school', 'creator']);

        return Pdf::loadView('receipts.payment', [
            'payment' => $payment,
            'receiptNumber' => $this->receiptNumber($payment),
            // Dates on the receipt are read at the school, not on the server.
            'issuedOn' => $payment->school?->clock()->format(now(), DateFormats::DATE) ?? now()->format(DateFormats::DATE),
        ])->setPaper('a4')->output();
    }
}
