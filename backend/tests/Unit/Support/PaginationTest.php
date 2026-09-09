<?php

namespace Tests\Unit\Support;

use App\Support\Pagination;
use PHPUnit\Framework\TestCase;

class PaginationTest extends TestCase
{
    public function test_it_defaults_to_20_when_no_per_page_is_given(): void
    {
        $this->assertSame(20, Pagination::resolvePerPage([]));
    }

    public function test_it_uses_the_requested_per_page_within_range(): void
    {
        $this->assertSame(50, Pagination::resolvePerPage(['per_page' => 50]));
    }

    public function test_it_caps_an_excessive_per_page_at_the_max(): void
    {
        $this->assertSame(100, Pagination::resolvePerPage(['per_page' => 5000]));
    }

    public function test_it_falls_back_to_the_default_for_a_zero_or_negative_per_page(): void
    {
        $this->assertSame(20, Pagination::resolvePerPage(['per_page' => 0]));
        $this->assertSame(20, Pagination::resolvePerPage(['per_page' => -10]));
    }

    public function test_it_accepts_a_custom_default_and_max(): void
    {
        $this->assertSame(10, Pagination::resolvePerPage([], default: 10));
        $this->assertSame(200, Pagination::resolvePerPage(['per_page' => 500], max: 200));
    }
}
