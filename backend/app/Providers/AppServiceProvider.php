<?php

namespace App\Providers;

use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\ServiceProvider;

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
    }
}
