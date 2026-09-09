<?php

namespace Tests\Feature\Api\V1;

use App\Enums\PaymentStatus;
use App\Enums\UserRole;
use App\Models\Payment;
use App\Models\School;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PaymentManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_can_record_a_payment_and_the_currency_is_copied_from_the_school(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create(['currency_code' => 'NGN']);

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/payments', [
            'school_id' => $school->id,
            'payment_type' => 'setup_fee',
            'amount' => '25000.00',
            'payment_date' => '2026-09-01',
            'payment_mode' => 'bank_transfer',
            'reference_number' => 'TXN-12345',
            'status' => 'paid',
        ]);

        $response->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('currency_code', 'NGN')
            ->assertJsonPath('amount', '25000.00')
            ->assertJsonPath('status', 'paid');
    }

    public function test_a_non_super_admin_cannot_record_a_payment(): void
    {
        $schoolAdmin = User::factory()->role(UserRole::SchoolAdmin)->create();
        $school = School::factory()->create();

        $this->actingAs($schoolAdmin, 'sanctum')
            ->postJson('/api/v1/payments', [
                'school_id' => $school->id,
                'payment_type' => 'setup_fee',
                'amount' => '1000.00',
                'payment_date' => '2026-09-01',
                'payment_mode' => 'cash',
                'status' => 'paid',
            ])
            ->assertForbidden()
            ->assertJsonPath('code', 'FORBIDDEN');
    }

    public function test_an_unauthenticated_request_cannot_list_payments(): void
    {
        $this->getJson('/api/v1/payments')->assertUnauthorized();
    }

    public function test_recording_a_payment_validates_required_fields_and_amount(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/payments', [
            'amount' => '-5',
        ]);

        $response->assertUnprocessable()
            ->assertJsonStructure([
                'details' => ['errors' => ['school_id', 'payment_type', 'amount', 'payment_date', 'payment_mode', 'status']],
            ]);
    }

    public function test_an_amount_with_more_than_two_decimal_places_is_rejected(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/payments', [
            'school_id' => $school->id,
            'payment_type' => 'SETUP_FEE',
            'amount' => '1000.999',
            'payment_date' => now()->toDateString(),
            'payment_mode' => 'CASH',
            'status' => 'PAID',
        ]);

        $response->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['amount']]]);
    }

    public function test_super_admin_can_filter_payments_by_school(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        Payment::factory()->forSchool($schoolA)->count(2)->create();
        Payment::factory()->forSchool($schoolB)->count(3)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson("/api/v1/payments?school_id={$schoolA->id}");

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_super_admin_can_update_a_payments_status(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $payment = Payment::factory()->status(PaymentStatus::Pending)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson("/api/v1/payments/{$payment->id}", ['status' => 'paid'])
            ->assertOk()
            ->assertJsonPath('status', 'paid');
    }

    public function test_a_payments_school_id_and_currency_cannot_be_changed_after_creation(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $originalSchool = School::factory()->create(['currency_code' => 'INR']);
        $otherSchool = School::factory()->create(['currency_code' => 'USD']);
        $payment = Payment::factory()->forSchool($originalSchool)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->patchJson("/api/v1/payments/{$payment->id}", [
            'school_id' => $otherSchool->id,
            'currency_code' => 'USD',
            'amount' => '999.00',
        ]);

        $response->assertOk()
            ->assertJsonPath('school_id', $originalSchool->id)
            ->assertJsonPath('currency_code', 'INR')
            ->assertJsonPath('amount', '999.00');
    }

    public function test_collection_summary_groups_totals_by_currency_and_never_blends_them(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $inrSchool = School::factory()->create(['currency_code' => 'INR']);
        $usdSchool = School::factory()->create(['currency_code' => 'USD']);

        Payment::factory()->forSchool($inrSchool)->status(PaymentStatus::Paid)->create(['amount' => '10000.00']);
        Payment::factory()->forSchool($inrSchool)->status(PaymentStatus::Paid)->create(['amount' => '5000.00']);
        Payment::factory()->forSchool($usdSchool)->status(PaymentStatus::Paid)->create(['amount' => '300.00']);
        Payment::factory()->forSchool($usdSchool)->status(PaymentStatus::Pending)->create(['amount' => '150.00']);

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/payments/summary');

        $response->assertOk();
        $totals = collect($response->json('total_by_currency'))->keyBy('currency_code');
        $this->assertSame('15000.00', $totals['INR']['total']);
        $this->assertSame('300.00', $totals['USD']['total']);
        $this->assertSame(1, $response->json('pending_count'));
    }
}
