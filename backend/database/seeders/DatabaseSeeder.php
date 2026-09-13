<?php

namespace Database\Seeders;

use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seeds only what a real deployment needs: the Super Admin who onboards
     * the first school.
     *
     * Nothing here creates sample or test data. This runs against production,
     * and a seeded account with a password anyone can read in the repository
     * would be an open door on day one - test data belongs in factories,
     * which the test suite builds per test.
     */
    public function run(): void
    {
        $this->call(SuperAdminSeeder::class);
    }
}
