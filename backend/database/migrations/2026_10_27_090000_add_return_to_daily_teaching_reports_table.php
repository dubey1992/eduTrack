<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * An HOD may send a teaching report back with a note (docs/teacher-app.md,
 * T7), not only mark it reviewed.
 *
 * A report is now in one of three states, read from these columns rather
 * than a status string, so no existing row needs rewriting:
 *
 * - **awaiting review** - neither `reviewed_by` nor `returned_at` is set;
 * - **reviewed** - `reviewed_by` is set (final, as before);
 * - **returned** - `returned_at` is set and `reviewed_by` is not. The teacher
 *   edits the report and sends it back, which clears `returned_at` and puts
 *   it in the HOD's queue again.
 *
 * `review_note` is the HOD's note - required when returning, optional when
 * reviewing - and stays on the report so the teacher can still read what was
 * asked after they have answered it. `returned_by` is kept so the teacher
 * is told who asked.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('daily_teaching_reports', function (Blueprint $table) {
            $table->string('review_note', 500)->nullable()->after('remarks');
            $table->timestamp('returned_at')->nullable()->after('reviewed_at');
            $table->foreignId('returned_by')->nullable()->after('returned_at')->constrained('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('daily_teaching_reports', function (Blueprint $table) {
            $table->dropConstrainedForeignId('returned_by');
            $table->dropColumn(['review_note', 'returned_at']);
        });
    }
};
