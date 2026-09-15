<?php

namespace App\Providers;

use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Single-resource API responses stay flat (no forced "data" wrapper),
        // matching the predictable response shape from CLAUDE.md rule 16.
        // Paginated resource collections still get data/links/meta - that
        // comes from Laravel's pagination response, not this wrap setting.
        JsonResource::withoutWrapping();

        // This is an API with a separate Flutter frontend, not a Blade app,
        // so the reset link points at the frontend's reset-password screen
        // rather than a Laravel-rendered "password.reset" route.
        ResetPassword::createUrlUsing(function ($user, string $token) {
            $frontendUrl = rtrim(config('app.frontend_url'), '/');

            return "{$frontendUrl}/reset-password?token={$token}&email={$user->getEmailForPasswordReset()}";
        });

        $this->configureRateLimiting();
    }

    /**
     * Limits on the endpoints that accept a password or hand out a reset
     * link - the only ones an attacker can attack without an account.
     *
     * Each is limited per account *and* per address. A school usually sits
     * behind one public IP, so limiting by address alone would let one
     * person mistyping their password lock out the whole staff room; keying
     * on the account stops that, and the looser per-address limit still
     * catches someone working through a list of addresses.
     */
    private function configureRateLimiting(): void
    {
        RateLimiter::for('login', fn (Request $request) => [
            Limit::perMinute(5)->by($this->accountKey($request)),
            Limit::perMinute(30)->by($request->ip()),
        ]);

        // A public write with no account behind it, so the only thing between
        // it and a script is this. Five a minute is more than any school
        // needs and less than any bot wants.
        RateLimiter::for('early-access', fn (Request $request) => Limit::perMinute(5)->by($request->ip()));

        // Tighter: each attempt sends a real email, so this is also a way to
        // spam somebody's inbox.
        RateLimiter::for('password-reset', fn (Request $request) => [
            Limit::perMinute(3)->by($this->accountKey($request)),
            Limit::perMinute(10)->by($request->ip()),
        ]);
    }

    /**
     * One attacker guessing one account, as opposed to one office.
     */
    private function accountKey(Request $request): string
    {
        return Str::lower((string) $request->input('email')).'|'.$request->ip();
    }
}
