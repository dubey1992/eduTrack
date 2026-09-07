<?php

namespace App\Providers;

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
    }
}
