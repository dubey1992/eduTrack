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
        Schema::create('staff_profiles', function (Blueprint $table) {
            $table->id();
            // 1:1 with users - kept as its own table rather than columns on
            // `users` since SUPER_ADMIN/SCHOOL_ADMIN accounts have no
            // employment profile (see CLAUDE.md rule 9: no unrelated nullable
            // clutter on a shared table).
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('employee_id', 30);
            $table->foreignId('department_id')->nullable()->constrained('departments')->nullOnDelete();
            $table->string('designation', 100)->nullable();
            $table->date('joining_date');
            $table->text('address')->nullable();
            $table->timestamps();

            $table->unique(['school_id', 'employee_id']);
            $table->index('department_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('staff_profiles');
    }
};
