<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A school asking to be let in.
 *
 * Not a school and not a user: a request is somebody who filled in a form on
 * the marketing page, and most of them will never become either. It carries
 * no school_id and belongs to no tenant - it is the one table in the system
 * that exists before a school does.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('early_access_requests', function (Blueprint $table) {
            $table->id();

            // What the school told us.
            $table->string('school_name', 150);
            $table->string('contact_name', 150);
            $table->string('contact_role', 100)->nullable();
            $table->string('email');
            $table->string('phone', 20);
            $table->string('city', 100);
            $table->string('country', 100);
            $table->unsignedInteger('expected_students')->nullable();
            $table->string('current_software', 150)->nullable();
            $table->text('message')->nullable();

            // What we have done about it.
            $table->string('status', 20)->default('new');
            $table->text('notes')->nullable();
            // The school this request became, if it became one. Kept if the
            // school is later removed - the request is still a record of who
            // asked, and when.
            $table->foreignId('converted_school_id')->nullable()->constrained('schools')->nullOnDelete();
            $table->foreignId('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();

            $table->timestamps();

            // The panel lists newest-first and filters by status.
            $table->index(['status', 'created_at']);
            // A school submitting the form twice should find its own open
            // request rather than create a second one.
            $table->index('email');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('early_access_requests');
    }
};
