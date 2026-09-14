<?php

namespace App\Services;

use Illuminate\Auth\Passwords\PasswordBroker;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;

/**
 * Email-based password reset only for now (Laravel's built-in broker).
 * Mobile-based reset needs the SMS provider abstraction from Phase 16 and
 * is deliberately deferred, not silently skipped - see CLAUDE.md rule 47.
 */
class PasswordResetService
{
    /**
     * Always looks the same to the caller whether or not the email exists,
     * so the API never reveals which emails are registered.
     */
    public function sendResetLink(string $email): void
    {
        Password::sendResetLink(['email' => $email]);
    }

    /**
     * @return bool true if the token was valid and the password was reset.
     */
    public function reset(string $email, string $token, string $password): bool
    {
        $status = Password::reset(
            ['email' => $email, 'token' => $token, 'password' => $password],
            function ($user, $newPassword) {
                // Choosing a password is choosing a password, however the
                // account got here - so an imported employee who uses the
                // reset link is no longer being asked to change it.
                $user->forceFill([
                    'password' => Hash::make($newPassword),
                    'must_change_password' => false,
                ])->save();
                $user->tokens()->delete();
            }
        );

        return $status === PasswordBroker::PASSWORD_RESET;
    }
}
