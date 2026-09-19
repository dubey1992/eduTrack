<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which registered WhatsApp template carries each event for a school.
 *
 * WhatsApp business messaging refuses free text unless the recipient wrote
 * first within the last day, so every message the school starts has to be a
 * template the provider approved beforehand. A row maps one event to the
 * template's name (a Content SID on Twilio, a template name on Meta), the
 * language it was approved in, and which of the event's tokens fill its
 * numbered parameters, in order. An event without a row is logged as skipped
 * on the WhatsApp channel, with that as the reason.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('whatsapp_templates', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('event', 50);
            $table->string('template_name', 120);
            $table->string('language', 10)->default('en');
            // Comma-separated token names, e.g. "student_name,date,school_name".
            $table->string('parameters', 255)->nullable();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['school_id', 'event']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('whatsapp_templates');
    }
};
