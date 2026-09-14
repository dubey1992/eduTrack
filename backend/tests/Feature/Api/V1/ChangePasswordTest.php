<?php

namespace Tests\Feature\Api\V1;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Changing your own password while signed in.
 *
 * This is what makes the generated password a bulk import hands out a
 * temporary one rather than a permanent one: the account is flagged, the
 * client keeps it here, and the flag only clears when the person picks
 * something the office never saw.
 */
class ChangePasswordTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_user_changes_their_own_password(): void
    {
        $user = User::factory()->create(['password' => 'old-password-1', 'must_change_password' => true]);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/auth/change-password', [
            'current_password' => 'old-password-1',
            'password' => 'new-password-1',
            'password_confirmation' => 'new-password-1',
        ])->assertOk()->assertJsonPath('message', 'Password changed successfully.');

        $user->refresh();

        $this->assertTrue(Hash::check('new-password-1', $user->password));
        $this->assertFalse($user->must_change_password);
    }

    public function test_the_new_password_works_at_the_login_screen(): void
    {
        $user = User::factory()->create(['password' => 'old-password-1']);

        $this->withToken($user->createToken('this-browser')->plainTextToken)
            ->postJson('/api/v1/auth/change-password', [
                'current_password' => 'old-password-1',
                'password' => 'new-password-1',
                'password_confirmation' => 'new-password-1',
            ])->assertOk();

        $this->postJson('/api/v1/auth/login', ['email' => $user->email, 'password' => 'new-password-1'])->assertOk();
        $this->postJson('/api/v1/auth/login', ['email' => $user->email, 'password' => 'old-password-1'])
            ->assertUnauthorized();
    }

    public function test_the_wrong_current_password_changes_nothing(): void
    {
        $user = User::factory()->create(['password' => 'old-password-1']);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/auth/change-password', [
            'current_password' => 'not-my-password',
            'password' => 'new-password-1',
            'password_confirmation' => 'new-password-1',
        ])
            ->assertStatus(422)
            ->assertJsonPath('details.errors.current_password.0', 'That is not your current password.');

        $this->assertTrue(Hash::check('old-password-1', $user->refresh()->password));
    }

    public function test_a_confirmation_that_does_not_match_is_refused(): void
    {
        $user = User::factory()->create(['password' => 'old-password-1']);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/auth/change-password', [
            'current_password' => 'old-password-1',
            'password' => 'new-password-1',
            'password_confirmation' => 'new-password-2',
        ])->assertStatus(422);
    }

    public function test_the_new_password_has_to_be_a_new_password(): void
    {
        $user = User::factory()->create(['password' => 'old-password-1', 'must_change_password' => true]);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/auth/change-password', [
            'current_password' => 'old-password-1',
            'password' => 'old-password-1',
            'password_confirmation' => 'old-password-1',
        ])
            ->assertStatus(422)
            ->assertJsonPath('details.errors.password.0', 'Choose a password you have not just been using.');

        $this->assertTrue($user->refresh()->must_change_password);
    }

    public function test_a_password_shorter_than_eight_characters_is_refused(): void
    {
        $user = User::factory()->create(['password' => 'old-password-1']);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/auth/change-password', [
            'current_password' => 'old-password-1',
            'password' => 'short',
            'password_confirmation' => 'short',
        ])->assertStatus(422);
    }

    public function test_changing_a_password_signs_out_every_other_session(): void
    {
        $user = User::factory()->create(['password' => 'old-password-1']);
        $user->createToken('another-browser');
        $here = $user->createToken('this-browser')->plainTextToken;

        $this->withToken($here)->postJson('/api/v1/auth/change-password', [
            'current_password' => 'old-password-1',
            'password' => 'new-password-1',
            'password_confirmation' => 'new-password-1',
        ])->assertOk();

        // If the temporary password reached the wrong person, this is where
        // that stops mattering. Asserted on the tokens themselves rather
        // than by making a second request, because a guard that has already
        // resolved a user inside one test keeps them.
        $this->assertSame(1, $user->tokens()->count());
        $this->assertSame('this-browser', $user->tokens()->first()->name);
    }

    public function test_a_signed_out_visitor_cannot_change_a_password(): void
    {
        $this->postJson('/api/v1/auth/change-password', [
            'current_password' => 'old-password-1',
            'password' => 'new-password-1',
            'password_confirmation' => 'new-password-1',
        ])->assertUnauthorized();
    }

    public function test_the_session_says_when_a_password_must_be_changed(): void
    {
        $user = User::factory()->create(['password' => 'old-password-1', 'must_change_password' => true]);

        $this->actingAs($user, 'sanctum')->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('must_change_password', true);
    }

    public function test_using_the_reset_link_also_clears_the_flag(): void
    {
        $user = User::factory()->create(['must_change_password' => true]);
        $token = app('auth.password.broker')->createToken($user);

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => $user->email,
            'token' => $token,
            'password' => 'new-password-1',
            'password_confirmation' => 'new-password-1',
        ])->assertOk();

        $this->assertFalse($user->refresh()->must_change_password);
    }
}
