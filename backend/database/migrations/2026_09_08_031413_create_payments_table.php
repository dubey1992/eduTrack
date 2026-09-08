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
        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('payment_type');
            $table->decimal('amount', 12, 2);
            // Snapshot of the school's currency at the time of payment - see
            // CLAUDE.md rule 5. Never re-derived from the school afterwards.
            $table->char('currency_code', 3);
            $table->date('payment_date');
            $table->string('payment_mode');
            $table->string('reference_number')->nullable();
            $table->text('notes')->nullable();
            $table->string('status');
            $table->foreignId('created_by')->constrained('users');
            $table->timestamps();

            $table->index('status');
            $table->index('payment_date');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('payments');
    }
};
