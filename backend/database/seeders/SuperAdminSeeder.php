<?php

namespace Database\Seeders;

use App\Enums\UserRole;
use App\Enums\UserStatus;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use RuntimeException;

/**
 * Creates the platform's first Super Admin - the account that onboards the
 * first school, and the only way into a freshly deployed instance.
 *
 * The password is read from the environment and never stored in this file:
 * the repository is not a safe place for a live credential, and anyone who
 * can read a commit could otherwise sign in as the platform owner.
 *
 * Safe to run again on a later deploy. If the account already exists it is
 * left exactly as it is, so a password the owner has since changed is never
 * silently reset back to whatever the environment happens to say.
 */
class SuperAdminSeeder extends Seeder
{
    public function run(): void
    {
        $email = (string) env('SUPER_ADMIN_EMAIL', 'super.admin@school365ai.com');
        $password = (string) env('SUPER_ADMIN_PASSWORD', '');

        if ($password === '') {
            throw new RuntimeException(
                'SUPER_ADMIN_PASSWORD is not set. Add it to .env before seeding; '
                .'there is deliberately no default, because a known password on a '
                .'public host is an open door.'
            );
        }

        $existing = User::where('email', $email)->first();

        if ($existing !== null) {
            $this->command?->warn("Super Admin {$email} already exists (id {$existing->id}) - left untouched.");

            return;
        }

        $user = User::create([
            'first_name' => (string) env('SUPER_ADMIN_FIRST_NAME', 'Super'),
            'last_name' => (string) env('SUPER_ADMIN_LAST_NAME', 'Admin'),
            'email' => $email,
            'mobile' => env('SUPER_ADMIN_MOBILE'),
            'password' => Hash::make($password),
            'role' => UserRole::SuperAdmin,
            'status' => UserStatus::Active,
            'school_id' => null,
        ]);

        $this->command?->info("Super Admin created: {$user->email} (id {$user->id}).");
    }
}
