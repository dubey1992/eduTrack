<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Brings existing addresses into line with the rule the User model now
 * enforces on write: an email is stored lowercase.
 *
 * Needed because the unique index on `users.email` only guarantees one account
 * per person if every row is in the same case. Under MySQL's case-insensitive
 * collation that was true by accident; under PostgreSQL it has to be true on
 * purpose, and it has to be true *before* the data is imported there, or two
 * rows that MySQL considered duplicates arrive as two separate accounts.
 *
 * Safe to run on the current MySQL database precisely because of that
 * collation: two addresses differing only in case cannot already exist, so
 * lowercasing them cannot collide. Running this the other way round - importing
 * first and normalising afterwards - is what would fail.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('users')
            ->whereRaw('email <> lower(email)')
            ->update(['email' => DB::raw('lower(email)')]);
    }

    public function down(): void
    {
        // Deliberately irreversible. The original capitalisation is not
        // recorded anywhere, and restoring a guess would be worse than
        // leaving addresses lowercase - which is valid for every mail server
        // and is what the application now writes anyway.
    }
};
