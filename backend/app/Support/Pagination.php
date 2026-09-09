<?php

namespace App\Support;

class Pagination
{
    /**
     * Reads `per_page` from a filters array (as every list endpoint's
     * `$request->only([...])` produces) and clamps it to a sane range, so a
     * client can ask for a bigger page without being able to request an
     * unbounded one.
     *
     * @param  array<string, mixed>  $filters
     */
    public static function resolvePerPage(array $filters, int $default = 20, int $max = 100): int
    {
        $requested = (int) ($filters['per_page'] ?? $default);

        return $requested > 0 ? min($max, $requested) : $default;
    }
}
