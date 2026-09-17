<?php

namespace Tests\Feature\Api\V1;

use App\Enums\PaymentStatus;
use App\Enums\UserRole;
use App\Models\Payment;
use App\Models\School;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The Super Admin's landing figures.
 *
 * The rest of the dashboard is covered with the group it rolls up
 * (GroupAdminTest, SchoolAdminGroupTest); this is the money card, which has a
 * rule of its own: CLAUDE.md rule 5, amounts grouped by currency and never
 * blended.
 */
class DashboardTest extends TestCase
{
    use RefreshDatabase;

    public function test_money_collected_is_listed_per_currency_in_a_fixed_order(): void
    {
        $root = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        // Written in an order the currencies do not sort in, so an order left
        // to the database's grouping would not come out alphabetical.
        foreach ([['USD', 12000], ['NGN', 250000.5], ['INR', 450000], ['USD', 500]] as [$currency, $amount]) {
            Payment::factory()->create([
                'school_id' => School::factory()->create(['currency_code' => $currency])->id,
                'currency_code' => $currency,
                'amount' => $amount,
                'paid_amount' => $amount,
            ]);
        }

        // A cancelled payment was never money received.
        Payment::factory()->status(PaymentStatus::Cancelled)->create(['currency_code' => 'EUR', 'amount' => 900]);

        $cards = collect($this->actingAs($root, 'sanctum')->getJson('/api/v1/dashboard')->assertOk()->json('cards'))
            ->keyBy('key');

        $this->assertSame('INR 450,000.00 + NGN 250,000.50 + USD 12,500.00', $cards['collected']['value']);
    }
}
