<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The fingerprint readers a school has (docs/biometric.md, B1).
 *
 * Staff punch in and out on these; the punches become the check-in and
 * check-out times on the staff register. This slice records the hardware and
 * nothing else - no punch is read until B2.
 *
 * **The serial number is unique across the platform, not per school.** It is
 * how an unauthenticated device says who it is: a box on a school's LAN posts
 * its serial and nothing more, and the serial is what tells us whose data it
 * is. Two schools claiming the same serial would make that question
 * unanswerable, so the database refuses it.
 *
 * `last_seen_at` is nullable and stays null until a device actually speaks
 * (B4). A device registered this morning and never heard from is a different
 * thing from one that stopped talking on Tuesday, and only this column tells
 * them apart.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('biometric_devices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('serial_number', 64)->unique();
            $table->string('name', 100);
            $table->string('location', 100)->nullable();
            $table->string('status')->default('active');
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamps();

            $table->index('school_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('biometric_devices');
    }
};
