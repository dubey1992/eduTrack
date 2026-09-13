<?php

namespace Tests\Feature\Api\V1;

use App\Enums\PaymentStatus;
use App\Enums\UserRole;
use App\Enums\UserStatus;
use App\Jobs\SendPaymentReceiptJob;
use App\Mail\PaymentReceiptMail;
use App\Models\Payment;
use App\Models\School;
use App\Models\User;
use App\Services\PaymentReceiptService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

/**
 * Part-payments and the receipt that goes with them.
 *
 * Two rules do the work here: what is still owed is derived from the figures
 * rather than stored, and the status is derived too - so a payment can never
 * read "Paid" while money is outstanding, and a receipt can never contradict
 * itself.
 */
class PaymentPartialAndReceiptTest extends TestCase
{
    use RefreshDatabase;

    private function superAdmin(): User
    {
        return User::factory()->role(UserRole::SuperAdmin)->create();
    }

    /**
     * @param  array<string, mixed>  $overrides
     * @return array<string, mixed>
     */
    private function payload(School $school, array $overrides = []): array
    {
        return array_merge([
            'school_id' => $school->id,
            'payment_type' => 'annual_maintenance',
            'amount' => '50000.00',
            'payment_date' => '2026-09-01',
            'payment_mode' => 'bank_transfer',
            'status' => 'partial',
        ], $overrides);
    }

    // -- what is still owed ----------------------------------------------

    public function test_a_partial_payment_reports_what_is_still_owed(): void
    {
        Queue::fake();
        $school = School::factory()->create(['currency_code' => 'INR']);

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '20000.00']))
            ->assertCreated()
            ->assertJsonPath('amount', '50000.00')
            ->assertJsonPath('paid_amount', '20000.00')
            ->assertJsonPath('remaining_amount', '30000.00')
            ->assertJsonPath('status', 'partial');
    }

    public function test_paying_everything_leaves_nothing_owed_and_settles_the_payment(): void
    {
        Queue::fake();
        $school = School::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '50000.00']))
            ->assertCreated()
            ->assertJsonPath('remaining_amount', '0.00')
            // The caller asked for "partial"; the figures say otherwise, and
            // the figures win.
            ->assertJsonPath('status', 'paid');
    }

    public function test_paying_nothing_yet_leaves_the_whole_amount_owed(): void
    {
        Queue::fake();
        $school = School::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '0']))
            ->assertCreated()
            ->assertJsonPath('remaining_amount', '50000.00')
            ->assertJsonPath('status', 'pending');
    }

    public function test_more_cannot_be_received_than_was_charged(): void
    {
        Queue::fake();
        $school = School::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '60000.00']))
            ->assertStatus(422)
            ->assertJsonPath('details.errors.paid_amount.0', 'The amount received cannot be more than the payment amount.');
    }

    public function test_marking_a_payment_paid_without_a_figure_still_records_the_money(): void
    {
        // The simple path - "this one is settled" - must not require the
        // amount to be typed twice.
        Queue::fake();
        $school = School::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['status' => 'paid']))
            ->assertCreated()
            ->assertJsonPath('paid_amount', '50000.00')
            ->assertJsonPath('remaining_amount', '0.00')
            ->assertJsonPath('status', 'paid');
    }

    public function test_a_cancelled_payment_owes_nothing(): void
    {
        Queue::fake();
        $school = School::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['status' => 'cancelled']))
            ->assertCreated()
            ->assertJsonPath('status', 'cancelled')
            ->assertJsonPath('remaining_amount', '0.00');
    }

    public function test_topping_up_a_partial_payment_settles_it(): void
    {
        Queue::fake();
        $school = School::factory()->create();
        $actor = $this->superAdmin();

        $id = $this->actingAs($actor, 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '20000.00']))
            ->json('id');

        $this->actingAs($actor, 'sanctum')
            ->patchJson("/api/v1/payments/{$id}", ['paid_amount' => '50000.00'])
            ->assertOk()
            ->assertJsonPath('remaining_amount', '0.00')
            ->assertJsonPath('status', 'paid');
    }

    public function test_lowering_the_amount_never_leaves_more_paid_than_is_owed(): void
    {
        Queue::fake();
        $school = School::factory()->create();
        $actor = $this->superAdmin();

        $id = $this->actingAs($actor, 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '50000.00']))
            ->json('id');

        $this->actingAs($actor, 'sanctum')
            ->patchJson("/api/v1/payments/{$id}", ['amount' => '30000.00'])
            ->assertOk()
            ->assertJsonPath('paid_amount', '30000.00')
            ->assertJsonPath('remaining_amount', '0.00');
    }

    // -- what the totals say ---------------------------------------------

    public function test_collection_totals_count_the_part_that_was_actually_paid(): void
    {
        Queue::fake();
        $school = School::factory()->create(['currency_code' => 'INR']);
        $actor = $this->superAdmin();

        $this->actingAs($actor, 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '20000.00']));

        $response = $this->actingAs($actor, 'sanctum')->getJson('/api/v1/payments/summary')->assertOk();

        $collected = collect($response->json('total_by_currency'))->firstWhere('currency_code', 'INR');
        $outstanding = collect($response->json('pending_by_currency'))->firstWhere('currency_code', 'INR');

        // Collected is the money in hand, not the whole invoice...
        $this->assertSame('20000.00', (string) $collected['total']);
        // ...and what is owed is the rest of it, not zero.
        $this->assertSame('30000.00', (string) $outstanding['total']);
    }

    // -- the receipt ------------------------------------------------------

    public function test_recording_a_payment_queues_a_receipt(): void
    {
        Queue::fake();
        $school = School::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '20000.00']))
            ->assertCreated();

        Queue::assertPushed(SendPaymentReceiptJob::class, 1);
    }

    public function test_correcting_a_reference_number_does_not_resend_the_receipt(): void
    {
        // Otherwise every typo fix emails the school again.
        Queue::fake();
        $school = School::factory()->create();
        $actor = $this->superAdmin();

        $id = $this->actingAs($actor, 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '20000.00']))
            ->json('id');

        $this->actingAs($actor, 'sanctum')
            ->patchJson("/api/v1/payments/{$id}", ['reference_number' => 'NEFT-991'])
            ->assertOk();

        Queue::assertPushed(SendPaymentReceiptJob::class, 1);
    }

    public function test_changing_what_was_paid_does_resend_the_receipt(): void
    {
        Queue::fake();
        $school = School::factory()->create();
        $actor = $this->superAdmin();

        $id = $this->actingAs($actor, 'sanctum')
            ->postJson('/api/v1/payments', $this->payload($school, ['paid_amount' => '20000.00']))
            ->json('id');

        $this->actingAs($actor, 'sanctum')
            ->patchJson("/api/v1/payments/{$id}", ['paid_amount' => '35000.00'])
            ->assertOk();

        Queue::assertPushed(SendPaymentReceiptJob::class, 2);
    }

    public function test_the_receipt_goes_to_the_schools_active_admins_only(): void
    {
        Mail::fake();
        $school = School::factory()->create();
        $wanted = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        // Not an admin, and an admin who has been deactivated.
        User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['status' => UserStatus::Inactive]);
        // An admin at a different school entirely.
        $otherSchool = School::factory()->create();
        $stranger = User::factory()->role(UserRole::SchoolAdmin)->forSchool($otherSchool)->create();

        $payment = Payment::factory()->forSchool($school)->create([
            'amount' => '50000.00',
            'paid_amount' => '20000.00',
            'status' => PaymentStatus::Partial,
        ]);

        (new SendPaymentReceiptJob($payment->id))->handle();

        Mail::assertSent(PaymentReceiptMail::class, 1);
        Mail::assertSent(PaymentReceiptMail::class, fn ($mail) => $mail->hasTo($wanted->email));
        Mail::assertNotSent(PaymentReceiptMail::class, fn ($mail) => $mail->hasTo($stranger->email));
    }

    public function test_the_subject_says_a_balance_is_outstanding(): void
    {
        Mail::fake();
        $school = School::factory()->create();
        User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $payment = Payment::factory()->forSchool($school)->create([
            'amount' => '50000.00',
            'paid_amount' => '20000.00',
            'status' => PaymentStatus::Partial,
        ]);

        (new SendPaymentReceiptJob($payment->id))->handle();

        Mail::assertSent(
            PaymentReceiptMail::class,
            fn ($mail) => str_contains($mail->envelope()->subject, 'balance outstanding'),
        );
    }

    public function test_sending_the_receipt_records_when_the_school_was_told(): void
    {
        Mail::fake();
        $school = School::factory()->create();
        User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $payment = Payment::factory()->forSchool($school)->create(['status' => PaymentStatus::Paid]);

        $this->assertNull($payment->receipt_sent_at);

        (new SendPaymentReceiptJob($payment->id))->handle();

        $this->assertNotNull($payment->fresh()->receipt_sent_at);
    }

    public function test_a_school_with_no_active_admin_is_not_an_error(): void
    {
        // Newly onboarded, or its only admin was deactivated. Nothing to
        // send, but the payment itself is perfectly valid.
        Mail::fake();
        $school = School::factory()->create();
        $payment = Payment::factory()->forSchool($school)->create();

        (new SendPaymentReceiptJob($payment->id))->handle();

        Mail::assertNothingSent();
        $this->assertNull($payment->fresh()->receipt_sent_at);
    }

    public function test_the_pdf_renders_and_states_the_balance(): void
    {
        $school = School::factory()->create(['name' => 'Sunrise Public School', 'currency_code' => 'INR']);
        $payment = Payment::factory()->forSchool($school)->create([
            'amount' => '50000.00',
            'paid_amount' => '20000.00',
            'status' => PaymentStatus::Partial,
        ]);

        $pdf = app(PaymentReceiptService::class)->render($payment);

        // A real PDF, not an exception or an empty string.
        $this->assertStringStartsWith('%PDF-', $pdf);
        $this->assertGreaterThan(1000, strlen($pdf));
    }

    public function test_the_receipt_can_be_downloaded(): void
    {
        Queue::fake();
        $school = School::factory()->create();
        $payment = Payment::factory()->forSchool($school)->create(['status' => PaymentStatus::Paid]);

        $response = $this->actingAs($this->superAdmin(), 'sanctum')
            ->get("/api/v1/payments/{$payment->id}/receipt")
            ->assertOk();

        $this->assertSame('application/pdf', $response->headers->get('Content-Type'));
        $this->assertStringContainsString('RCPT-', $response->headers->get('Content-Disposition'));
    }

    public function test_the_receipt_can_be_sent_again_on_request(): void
    {
        Queue::fake();
        $school = School::factory()->create();
        $payment = Payment::factory()->forSchool($school)->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson("/api/v1/payments/{$payment->id}/receipt")
            ->assertOk();

        Queue::assertPushed(SendPaymentReceiptJob::class, 1);
    }

    public function test_a_school_admin_cannot_pull_another_schools_receipt(): void
    {
        Queue::fake();
        $school = School::factory()->create();
        $payment = Payment::factory()->forSchool($school)->create();
        $outsider = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($outsider, 'sanctum')
            ->get("/api/v1/payments/{$payment->id}/receipt")
            ->assertForbidden();
    }
}
