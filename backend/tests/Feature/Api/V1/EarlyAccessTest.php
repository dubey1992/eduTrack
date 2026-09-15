<?php

namespace Tests\Feature\Api\V1;

use App\Enums\EarlyAccessStatus;
use App\Enums\UserRole;
use App\Models\EarlyAccessRequest;
use App\Models\School;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

/**
 * Schools asking to be let in.
 *
 * The one write in the API with no account behind it, which makes it the one
 * that has to assume every caller is a stranger: it is throttled, it validates
 * everything, and it tells whoever submits it nothing about who else has.
 */
class EarlyAccessTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // The throttle is real and the tests submit repeatedly; each one
        // starts with a clean allowance.
        RateLimiter::clear('early-access');
    }

    /**
     * @param  array<string, mixed>  $overrides
     * @return array<string, mixed>
     */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'school_name' => 'Greenfield High',
            'contact_name' => 'Priya Nair',
            'contact_role' => 'Principal',
            'email' => 'priya@greenfield.test',
            'phone' => '+91 9876543210',
            'city' => 'Pune',
            'country' => 'India',
            'expected_students' => 850,
            'current_software' => 'Spreadsheets',
            'message' => 'We open a second campus in June.',
        ], $overrides);
    }

    private function superAdmin(): User
    {
        return User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);
    }

    // ── the public form ─────────────────────────────────────────────────

    public function test_a_school_can_ask_for_access_without_an_account(): void
    {
        $this->postJson('/api/v1/early-access', $this->payload())
            ->assertCreated()
            ->assertJsonPath('message', 'Thanks - we have your details and will be in touch soon.');

        $this->assertDatabaseHas('early_access_requests', [
            'school_name' => 'Greenfield High',
            'email' => 'priya@greenfield.test',
            'expected_students' => 850,
            'status' => 'new',
        ]);
    }

    public function test_the_form_says_what_it_needs(): void
    {
        $response = $this->postJson('/api/v1/early-access', [])->assertStatus(422);

        foreach (['school_name', 'contact_name', 'email', 'phone', 'city', 'country'] as $field) {
            $response->assertJsonStructure(['details' => ['errors' => [$field]]]);
        }
    }

    public function test_a_phone_number_without_a_country_code_is_refused(): void
    {
        // Multi-nation from the first contact: a bare number is not enough to
        // call anybody back on.
        $this->postJson('/api/v1/early-access', $this->payload(['phone' => '9876543210']))
            ->assertStatus(422)
            ->assertJsonPath('details.errors.phone.0', 'Include the country code, like +91 9876543210.');
    }

    public function test_the_size_is_optional_because_plenty_of_people_do_not_know(): void
    {
        $this->postJson('/api/v1/early-access', $this->payload(['expected_students' => null]))->assertCreated();

        $this->assertDatabaseHas('early_access_requests', ['expected_students' => null]);
    }

    public function test_an_absurd_student_count_is_refused(): void
    {
        $this->postJson('/api/v1/early-access', $this->payload(['expected_students' => 900000]))
            ->assertStatus(422);
    }

    public function test_the_same_school_asking_twice_updates_its_own_request(): void
    {
        // Somebody re-reading the page and filling the form in again is not
        // two schools, and a panel full of duplicates is one nobody trusts.
        $this->postJson('/api/v1/early-access', $this->payload())->assertCreated();
        $this->postJson('/api/v1/early-access', $this->payload(['school_name' => 'Greenfield High School']))
            ->assertCreated();

        $this->assertSame(1, EarlyAccessRequest::query()->count());
        // Their latest answer wins - they may be correcting a typo.
        $this->assertSame('Greenfield High School', EarlyAccessRequest::query()->first()->school_name);
    }

    public function test_asking_again_keeps_the_place_somebody_already_gave_it(): void
    {
        $existing = EarlyAccessRequest::factory()
            ->status(EarlyAccessStatus::Contacted)
            ->create(['email' => 'priya@greenfield.test', 'notes' => 'Called on Tuesday.']);

        $this->postJson('/api/v1/early-access', $this->payload())->assertCreated();

        $existing->refresh();
        $this->assertSame(EarlyAccessStatus::Contacted, $existing->status);
        $this->assertSame('Called on Tuesday.', $existing->notes);
    }

    public function test_a_school_that_was_turned_down_before_can_ask_again(): void
    {
        EarlyAccessRequest::factory()
            ->status(EarlyAccessStatus::Declined)
            ->create(['email' => 'priya@greenfield.test']);

        $this->postJson('/api/v1/early-access', $this->payload())->assertCreated();

        // A fresh approach after a "no" is genuinely new.
        $this->assertSame(2, EarlyAccessRequest::query()->count());
    }

    public function test_the_form_is_throttled(): void
    {
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/early-access', $this->payload(['email' => "school{$i}@example.test"]))
                ->assertCreated();
        }

        $this->postJson('/api/v1/early-access', $this->payload(['email' => 'one.too.many@example.test']))
            ->assertStatus(429);
    }

    public function test_the_form_tells_a_stranger_nothing_about_anyone_else(): void
    {
        EarlyAccessRequest::factory()->create(['email' => 'priya@greenfield.test']);

        $response = $this->postJson('/api/v1/early-access', $this->payload())->assertCreated();

        // Same answer whether it was new or an update - "you already applied"
        // would confirm an address to anybody who guessed it.
        $this->assertSame(
            ['message' => 'Thanks - we have your details and will be in touch soon.'],
            $response->json(),
        );
    }

    // ── the panel ───────────────────────────────────────────────────────

    public function test_a_super_admin_sees_the_requests_newest_first(): void
    {
        $older = EarlyAccessRequest::factory()->create(['school_name' => 'First In']);
        $newer = EarlyAccessRequest::factory()->create(['school_name' => 'Just Arrived']);

        $names = collect(
            $this->actingAs($this->superAdmin(), 'sanctum')->getJson('/api/v1/early-access')->assertOk()->json('data')
        )->pluck('school_name');

        $this->assertSame(['Just Arrived', 'First In'], $names->all());
        $this->assertNotSame($older->id, $newer->id);
    }

    public function test_the_list_can_be_filtered_by_status_and_searched(): void
    {
        EarlyAccessRequest::factory()->create(['school_name' => 'Greenfield High']);
        EarlyAccessRequest::factory()->status(EarlyAccessStatus::Declined)->create(['school_name' => 'Nope Academy']);

        $admin = $this->superAdmin();

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/v1/early-access?status=declined')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.school_name', 'Nope Academy');

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/v1/early-access?q=Greenfield')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.school_name', 'Greenfield High');
    }

    public function test_a_request_shows_everything_the_school_told_us(): void
    {
        $this->postJson('/api/v1/early-access', $this->payload())->assertCreated();
        $id = EarlyAccessRequest::query()->first()->id;

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->getJson("/api/v1/early-access/{$id}")
            ->assertOk()
            ->assertJsonPath('contact_role', 'Principal')
            ->assertJsonPath('current_software', 'Spreadsheets')
            ->assertJsonPath('message', 'We open a second campus in June.')
            ->assertJsonPath('status_label', 'New');
    }

    public function test_a_super_admin_moves_a_request_along_and_leaves_a_note(): void
    {
        $request = EarlyAccessRequest::factory()->create();
        $admin = $this->superAdmin();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/early-access/{$request->id}", [
                'status' => 'contacted',
                'notes' => 'Spoke to the principal; demo on Friday.',
            ])
            ->assertOk()
            ->assertJsonPath('status', 'contacted')
            ->assertJsonPath('notes', 'Spoke to the principal; demo on Friday.')
            ->assertJsonPath('reviewed_by_name', $admin->name);

        $this->assertNotNull($request->refresh()->reviewed_at);
    }

    public function test_converted_cannot_be_claimed_by_hand(): void
    {
        // It means a school exists. Saying so without one makes the list
        // disagree with reality.
        $request = EarlyAccessRequest::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->patchJson("/api/v1/early-access/{$request->id}", ['status' => 'converted'])
            ->assertStatus(422)
            ->assertJsonPath(
                'details.errors.status.0',
                'A request becomes Converted by onboarding the school, not by saying so.',
            );
    }

    // ── becoming a school ───────────────────────────────────────────────

    public function test_onboarding_a_school_from_a_request_marks_it_converted(): void
    {
        $request = EarlyAccessRequest::factory()->create(['school_name' => 'Greenfield High']);

        $response = $this->actingAs($this->superAdmin(), 'sanctum')->postJson('/api/v1/schools', [
            'early_access_request_id' => $request->id,
            'name' => 'Greenfield High',
            'email' => 'office@greenfield.test',
            'phone' => '+91 9876543210',
            'address' => '1 Green Road',
            'city' => 'Pune',
            'state' => 'MH',
            'country' => 'India',
            'postal_code' => '411001',
            'currency_code' => 'INR',
            'timezone' => 'Asia/Kolkata',
        ])->assertCreated();

        $request->refresh();

        $this->assertSame(EarlyAccessStatus::Converted, $request->status);
        $this->assertSame($response->json('id'), $request->converted_school_id);
        $this->assertNotNull($request->reviewed_at);
    }

    public function test_onboarding_a_school_normally_touches_no_request(): void
    {
        EarlyAccessRequest::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')->postJson('/api/v1/schools', [
            'name' => 'Unrelated School',
            'email' => 'office@unrelated.test',
            'phone' => '+91 9876543210',
            'address' => '1 Road',
            'city' => 'Pune',
            'state' => 'MH',
            'country' => 'India',
            'postal_code' => '411001',
            'currency_code' => 'INR',
            'timezone' => 'Asia/Kolkata',
        ])->assertCreated();

        $this->assertSame(EarlyAccessStatus::New, EarlyAccessRequest::query()->first()->status);
    }

    public function test_a_converted_request_still_names_the_school_it_became(): void
    {
        $school = School::factory()->create(['name' => 'Greenfield High']);
        $request = EarlyAccessRequest::factory()->create([
            'status' => EarlyAccessStatus::Converted,
            'converted_school_id' => $school->id,
        ]);

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->getJson("/api/v1/early-access/{$request->id}")
            ->assertOk()
            ->assertJsonPath('converted_school_name', 'Greenfield High');
    }

    public function test_a_request_outlives_the_school_it_became(): void
    {
        // The request is still a record of who asked, and when.
        $school = School::factory()->create();
        $request = EarlyAccessRequest::factory()->create([
            'status' => EarlyAccessStatus::Converted,
            'converted_school_id' => $school->id,
        ]);

        $school->delete();

        $this->assertDatabaseHas('early_access_requests', [
            'id' => $request->id,
            'converted_school_id' => null,
            'status' => 'converted',
        ]);
    }

    // ── who may look ────────────────────────────────────────────────────

    public function test_a_school_admin_cannot_read_other_schools_enquiries(): void
    {
        $request = EarlyAccessRequest::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/early-access')->assertForbidden();
        $this->actingAs($admin, 'sanctum')->getJson("/api/v1/early-access/{$request->id}")->assertForbidden();
        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/early-access/{$request->id}", ['status' => 'declined'])
            ->assertForbidden();
    }

    public function test_a_group_admin_cannot_either(): void
    {
        // Signups are platform business, same as onboarding and payments.
        $group = School::factory()->create();
        $admin = User::factory()->role(UserRole::GroupAdmin)->forSchool($group)->create();

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/early-access')->assertForbidden();
    }

    public function test_a_stranger_cannot_read_the_panel(): void
    {
        EarlyAccessRequest::factory()->create();

        $this->getJson('/api/v1/early-access')->assertUnauthorized();
    }
}
