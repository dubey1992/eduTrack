<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Marks an account whose password was set by somebody else.
     *
     * A bulk import generates a password per person, which means the school
     * office knows it. Until the owner replaces it, it is a shared secret
     * rather than a credential, so the account is flagged and the app makes
     * changing it the first thing that happens.
     *
     * Existing accounts chose their own passwords, so they default to false.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('must_change_password')->default(false)->after('password');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('must_change_password');
        });
    }
};
