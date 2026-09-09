<?php

namespace Tests\Feature\Api\V1;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_user_can_log_in_with_valid_credentials(): void
    {
        $user = User::factory()->create(['password' => 'correct-password']);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'correct-password',
        ]);

        $response->assertOk()
            ->assertJsonStructure(['user' => ['id', 'name', 'email'], 'token'])
            ->assertJsonPath('user.email', $user->email);
    }

    public function test_login_is_rejected_with_invalid_credentials(): void
    {
        $user = User::factory()->create(['password' => 'correct-password']);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'wrong-password',
        ]);

        $response->assertUnauthorized()
            ->assertJsonPath('code', 'UNAUTHENTICATED')
            // The client must see the actual reason, not a generic
            // "authentication required" message meant for protected routes.
            ->assertJsonPath('message', 'These credentials do not match our records.');

        // `details` must serialize as a JSON *object* ({}), never an array
        // ([]) - the Flutter client casts it to Map<String, dynamic> and a
        // bare PHP [] json_encodes as [], which crashes that cast. Asserting
        // on the raw body is required here since assertJsonPath()/->json()
        // decode both {} and [] into an identical empty PHP array, hiding
        // the exact bug this guards against.
        $this->assertStringContainsString('"details":{}', $response->getContent());
    }

    public function test_login_requires_email_and_password(): void
    {
        $response = $this->postJson('/api/v1/auth/login', []);

        $response->assertUnprocessable()
            ->assertJsonPath('code', 'VALIDATION_ERROR')
            ->assertJsonStructure(['details' => ['errors' => ['email', 'password']]]);
    }

    public function test_me_endpoint_requires_authentication(): void
    {
        $response = $this->getJson('/api/v1/me');

        $response->assertUnauthorized()
            ->assertJsonPath('code', 'UNAUTHENTICATED');
    }

    public function test_authenticated_user_can_fetch_their_own_profile(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user, 'sanctum')->getJson('/api/v1/me');

        $response->assertOk()
            ->assertJsonPath('id', $user->id)
            ->assertJsonPath('email', $user->email)
            ->assertJsonMissing(['password']);
    }

    public function test_a_user_can_log_out_and_their_token_is_revoked(): void
    {
        $user = User::factory()->create(['password' => 'correct-password']);

        $token = $user->createToken('api-token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson('/api/v1/auth/logout');

        $response->assertOk();

        // The auth guard caches its resolved user for the lifetime of a
        // single test's application instance, so a second request must
        // force it to re-resolve rather than reuse that cached user.
        $this->app['auth']->forgetGuards();

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/v1/me')
            ->assertUnauthorized();
    }

    public function test_a_deactivated_user_cannot_log_in(): void
    {
        $user = User::factory()->inactive()->create(['password' => 'correct-password']);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'correct-password',
        ]);

        $response->assertForbidden()
            ->assertJsonPath('code', 'ACCOUNT_INACTIVE');
    }

    public function test_an_expired_token_is_rejected(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('api-token', ['*'], now()->subMinute())->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/v1/me')
            ->assertUnauthorized();
    }
}
