<?php

namespace App\Jobs;

use App\Enums\UserRole;
use App\Enums\UserStatus;
use App\Mail\PaymentReceiptMail;
use App\Models\Payment;
use App\Models\User;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Emails the receipt to the school's admins.
 *
 * Queued, because rendering a PDF and talking to an SMTP server has no
 * business holding up the person recording the payment - and a mail server
 * being slow or down must never be the reason a payment fails to save.
 */
class SendPaymentReceiptJob implements ShouldQueue
{
    use Queueable;

    public function __construct(public readonly int $paymentId) {}

    public function handle(): void
    {
        $payment = Payment::with(['school', 'creator'])->find($this->paymentId);

        // Deleted between dispatch and delivery: nothing to send, and
        // nothing wrong either.
        if ($payment === null) {
            return;
        }

        $recipients = User::query()
            ->where('school_id', $payment->school_id)
            ->where('role', UserRole::SchoolAdmin)
            ->where('status', UserStatus::Active)
            ->whereNotNull('email')
            ->pluck('email')
            ->all();

        if ($recipients === []) {
            // A school with no active admin is a real situation - newly
            // onboarded, or its only admin deactivated. Worth a line in the
            // log so it can be noticed, but not worth failing the job and
            // retrying forever.
            Log::info('No active School Admin to send a payment receipt to', [
                'payment_id' => $payment->id,
                'school_id' => $payment->school_id,
            ]);

            return;
        }

        try {
            Mail::to($recipients)->send(new PaymentReceiptMail($payment));
        } catch (Throwable $e) {
            Log::error('Could not email a payment receipt', [
                'payment_id' => $payment->id,
                'message' => $e->getMessage(),
            ]);

            throw $e;
        }

        // Records that the school has been told, and when - what the
        // "Receipt sent" line on the payment screen reads.
        $payment->forceFill(['receipt_sent_at' => now()])->saveQuietly();
    }
}
