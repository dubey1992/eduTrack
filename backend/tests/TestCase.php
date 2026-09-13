<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\Cache;

abstract class TestCase extends BaseTestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        // Rate limiter counters live in the cache, which is not rolled back
        // the way the database is. Without this, a test that signs in a few
        // times leaves its tally behind and the next one is throttled for
        // reasons that have nothing to do with what it is checking.
        Cache::flush();
    }
}
