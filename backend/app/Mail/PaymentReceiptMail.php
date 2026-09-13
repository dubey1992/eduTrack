<?php

namespace App\Mail;

use App\Enums\PaymentStatus;
use App\Models\Payment;
use App\Services\PaymentReceiptService;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Attachment;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * The receipt email to a school's admins, with the PDF attached.
 *
 * The subject says where the payment stands, so a part-payment is obvious in
 * an inbox without opening the attachment.
 */
class PaymentReceiptMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(public readonly Payment $payment) {}

    public function envelope(): Envelope
    {
        $receipts = app(PaymentReceiptService::class);
        $number = $receipts->receiptNumber($this->payment);

        $subject = match ($this->payment->status) {
            PaymentStatus::Paid => "Payment receipt {$number} - paid in full",
            PaymentStatus::Partial => "Payment receipt {$number} - balance outstanding",
            PaymentStatus::Cancelled => "Payment {$number} - cancelled",
            PaymentStatus::Pending => "Payment {$number} - awaiting payment",
        };

        return new Envelope(subject: $subject);
    }

    public function content(): Content
    {
        return new Content(
            markdown: 'mail.payments.receipt',
            with: [
                'payment' => $this->payment,
                'receiptNumber' => app(PaymentReceiptService::class)->receiptNumber($this->payment),
            ],
        );
    }

    /**
     * @return array<int, Attachment>
     */
    public function attachments(): array
    {
        $receipts = app(PaymentReceiptService::class);

        return [
            Attachment::fromData(fn () => $receipts->render($this->payment), $receipts->fileName($this->payment))
                ->withMime('application/pdf'),
        ];
    }
}
