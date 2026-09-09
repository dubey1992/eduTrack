<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // Distinguishes a School Admin a SUPER_ADMIN onboarded (can
            // create further admin accounts for their school) from a Sub
            // Admin a School Admin created themselves (same SCHOOL_ADMIN
            // role and permissions everywhere else in the app, but cannot
            // create any admin account - see UserPolicy::create()). Kept
            // as a flag on the existing role rather than a new UserRole
            // case specifically so every other policy in the app treats
            // both identically without needing to know this distinction.
            $table->boolean('is_sub_admin')->default(false)->after('role');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('is_sub_admin');
        });
    }
};
