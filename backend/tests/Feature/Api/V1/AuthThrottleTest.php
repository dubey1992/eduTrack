<?php

namespace Tests\Feature\Api\V1;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Brute-force protection on the endpoints reachable without a token.
 *
 * The shape matters as much as the limit: a school usually sits behind one
 * public IP, so limiting by address alone would let one person mistyping
 * their password lock out every colleague in the building. Each limit is
 * keyed on the account as well, with a looser per-address limit behind it.
 */
class AuthThrottleTest extends TestCase
{
    use RefreshDatabase;

    private function attemptLogin(string $email, string $password = 'wrong-password')
    {
        return $this->postJson('/api/v1/auth/login', ['email' => $email, 'password' => $password]);
    }

    public function test_repeated_failed_logins_against_one_account_are_blocked(): void
    {
        $user = User::factory()->create(['password' => 'correct-password']);

        for ($attempt = 1; $attempt <= 5; $attempt++) {
            $this->attemptLogin($user->email)->assertUnauthorized();
        }

        $this->attemptLogin($user->email)
            ->assertStatus(429)
            ->assertJsonPath('code', 'TOO_MANY_REQUESTS');
    }

    public function test_the_right_password_does_not_get_through_once_the_limit_is_hit(): void
    {
        // Otherwise the limit is decorative: an attacker who guesses correctly
        // on the sixth try would still be let in.
        $user = User::factory()->create(['password' => 'correct-password']);

        for ($attempt = 1; $attempt <= 5; $attempt++) {
            $this->attemptLogin($user->email)->assertUnauthorized();
        }

        $this->attemptLogin($user->email, 'correct-password')->assertStatus(429);
    }

    public function test_one_locked_out_colleague_does_not_lock_out_the_rest_of_the_school(): void
    {
        // Same address throughout - which is what a staff room looks like.
        $mistyping = User::factory()->create(['password' => 'correct-password']);
        $colleague = User::factory()->create(['password' => 'correct-password']);

        for ($attempt = 1; $attempt <= 6; $attempt++) {
            $this->attemptLogin($mistyping->email);
        }

        $this->attemptLogin($colleague->email, 'correct-password')->assertOk();
    }

    public function test_someone_working_through_a_list_of_accounts_is_still_stopped(): void
    {
        // Rotating the address key would defeat the per-account limit, so the
        // looser per-address limit has to catch it.
        for ($attempt = 1; $attempt <= 30; $attempt++) {
            $this->attemptLogin("nobody{$attempt}@example.test");
        }

        $victim = User::factory()->create(['password' => 'correct-password']);

        $this->attemptLogin($victim->email, 'correct-password')->assertStatus(429);
    }

    public function test_a_successful_login_is_not_blocked_by_ordinary_use(): void
    {
        $user = User::factory()->create(['password' => 'correct-password']);

        $this->attemptLogin($user->email, 'correct-password')->assertOk();
        $this->attemptLogin($user->email, 'correct-password')->assertOk();
    }

    public function test_password_reset_requests_are_limited_per_account(): void
    {
        $user = User::factory()->create();

        for ($attempt = 1; $attempt <= 3; $attempt++) {
            $this->postJson('/api/v1/auth/forgot-password', ['email' => $user->email])->assertOk();
        }

        // Each request sends a real email, so this is also a way to bury
        // somebody in messages.
        $this->postJson('/api/v1/auth/forgot-password', ['email' => $user->email])
            ->assertStatus(429)
            ->assertJsonPath('code', 'TOO_MANY_REQUESTS');
    }

    public function test_a_throttled_response_still_uses_the_standard_error_shape(): void
    {
        $user = User::factory()->create(['password' => 'correct-password']);

        for ($attempt = 1; $attempt <= 6; $attempt++) {
            $this->attemptLogin($user->email);
        }

        $response = $this->attemptLogin($user->email)->assertStatus(429);

        $response->assertJsonStructure(['code', 'message', 'details']);
        // `details` must serialize as an object, not an array - the Flutter
        // client casts it to Map<String, dynamic>.
        $this->assertStringContainsString('"details":{}', $response->getContent());
    }
}
