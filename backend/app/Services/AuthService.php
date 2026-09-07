<?php

namespace App\Services;

use App\Exceptions\AccountInactiveException;
use App\Models\User;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Support\Facades\Auth;

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
        if (! Auth::attempt(['email' => $email, 'password' => $password])) {
            throw new AuthenticationException('These credentials do not match our records.');
        }

        /** @var User $user */
        $user = Auth::user();

        if (! $user->isActive()) {
            Auth::logout();

            throw new AccountInactiveException;
        }

        $token = $user->createToken('api-token')->plainTextToken;

        return [$user, $token];
    }

    public function logout(User $user): void
    {
        $user->currentAccessToken()->delete();
    }
}
