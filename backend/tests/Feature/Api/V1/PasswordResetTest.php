<?php

namespace Tests\Feature\Api\V1;

use App\Models\User;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Password;
use Tests\TestCase;

class PasswordResetTest extends TestCase
{
    use RefreshDatabase;

    public function test_forgot_password_returns_a_generic_message_for_a_known_email(): void
    {
        $user = User::factory()->create();

        $this->postJson('/api/v1/auth/forgot-password', ['email' => $user->email])
            ->assertOk()
            ->assertJsonPath('message', 'If an account exists for that email, a password reset link has been sent.');
    }

    public function test_forgot_password_returns_the_same_generic_message_for_an_unknown_email(): void
    {
        $this->postJson('/api/v1/auth/forgot-password', ['email' => 'nobody@example.com'])
            ->assertOk()
            ->assertJsonPath('message', 'If an account exists for that email, a password reset link has been sent.');
    }

    public function test_a_user_can_reset_their_password_with_a_valid_token(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);
        $token = Password::createToken($user);

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => $user->email,
            'token' => $token,
            'password' => 'brand-new-password',
        ])->assertOk();

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'brand-new-password',
        ])->assertOk();
    }

    public function test_reset_password_is_rejected_with_an_invalid_token(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => $user->email,
            'token' => 'not-a-real-token',
            'password' => 'brand-new-password',
        ])->assertUnprocessable()->assertJsonPath('code', 'INVALID_RESET_TOKEN');

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'old-password',
        ])->assertOk();
    }

    public function test_the_password_reset_email_is_branded_and_links_to_the_frontend(): void
    {
        $user = User::factory()->create(['email' => 'priya.sharma@example.com']);

        $html = (string) (new ResetPassword('a-reset-token'))->toMail($user)->render();

        $this->assertStringContainsString(config('app.name'), $html);
        $this->assertStringContainsString('Smarter Schools. Brighter Futures.', $html);
        // The button's inlined style, not just an unstyled link - proves the
        // brand color (not Laravel's stock black) actually made it into the
        // rendered HTML, not just the source theme.css.
        $this->assertStringContainsString('#2563eb', $html);
        // Points at the Flutter app's own reset screen, never a Laravel
        // Blade route the SPA doesn't have (see AppServiceProvider::boot).
        // "&" is HTML-entity-encoded to "&amp;" inside the rendered href.
        $this->assertStringContainsString(
            rtrim(config('app.frontend_url'), '/').'/reset-password?token=a-reset-token&amp;email=priya.sharma@example.com',
            $html
        );
    }

    public function test_resetting_a_password_revokes_existing_tokens(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);
        $token = $user->createToken('api-token')->plainTextToken;
        $resetToken = Password::createToken($user);

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => $user->email,
            'token' => $resetToken,
            'password' => 'brand-new-password',
        ])->assertOk();

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/v1/me')
            ->assertUnauthorized();
    }
}
