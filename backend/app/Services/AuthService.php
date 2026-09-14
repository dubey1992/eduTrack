<?php

namespace App\Services;

use App\Exceptions\AccountInactiveException;
use App\Models\User;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;

class AuthService
{
    /**
     * Attempt to authenticate a user by email and password, returning a new
     * Sanctum API token on success.
     *
     * @throws AuthenticationException|AccountInactiveException
     */
    public function login(string $email, string $password): array
    {
        // Named rather than "whichever guard is current": every other route
        // in the API authenticates through sanctum, and checking a password
        // is the one thing sanctum's guard cannot do.
        $guard = Auth::guard('web');

        if (! $guard->attempt(['email' => $email, 'password' => $password])) {
            throw new AuthenticationException('These credentials do not match our records.');
        }

        /** @var User $user */
        $user = $guard->user();

        if (! $user->isActive()) {
            $guard->logout();

            throw new AccountInactiveException;
        }

        $token = $user->createToken('api-token')->plainTextToken;

        return [$user, $token];
    }

    /**
     * Sets a new password for the signed-in user.
     *
     * The current password has already been checked by ChangePasswordRequest.
     * Every other token is revoked - if an imported account's temporary
     * password reached the wrong person, this is the moment that stops
     * mattering - while the token in the caller's hand keeps working, so
     * nobody is signed out of the browser they are changing it from.
     */
    public function changePassword(User $user, string $newPassword): void
    {
        $user->forceFill([
            'password' => Hash::make($newPassword),
            'must_change_password' => false,
        ])->save();

        $current = $user->currentAccessToken();

        $user->tokens()
            ->when($current !== null, fn ($query) => $query->whereKeyNot($current->getKey()))
            ->delete();
    }

    public function logout(User $user): void
    {
        $user->currentAccessToken()->delete();
    }
}
