<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Who School365ai is, as a business: the issuer printed on the receipt a
 * school gets for paying the platform (docs/pdf-design.md, phase 5) - legal
 * and trading name, address, contacts, tax and company registration numbers,
 * logo. Set by the Super Admin on the Company details screen, so nobody needs
 * a developer to change them.
 *
 * One row at most, like mail_settings. Until it exists, documents print
 * "School365ai" and nothing more.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('company_profiles', function (Blueprint $table) {
            $table->id();
            $table->string('legal_name', 150);
            $table->string('trading_name', 100)->nullable();
            $table->string('address', 255)->nullable();
            $table->string('city', 100)->nullable();
            $table->string('state', 100)->nullable();
            $table->string('postal_code', 20)->nullable();
            $table->string('country', 100)->nullable();
            $table->string('phone', 30)->nullable();
            $table->string('email', 150)->nullable();
            $table->string('website', 150)->nullable();

            // GSTIN in India; VAT or sales-tax number elsewhere.
            $table->string('tax_number', 30)->nullable();

            // CIN in India; the company registration number elsewhere.
            $table->string('registration_number', 30)->nullable();
            $table->string('logo_url', 255)->nullable();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('company_profiles');
    }
};
