<?php

namespace App\Enums;

enum PaymentType: string
{
    case SetupFee = 'setup_fee';
    case AnnualMaintenance = 'annual_maintenance';
    case AdditionalService = 'additional_service';
    case Other = 'other';

    public function label(): string
    {
        return match ($this) {
            self::SetupFee => 'Setup Fee',
            self::AnnualMaintenance => 'Annual Maintenance',
            self::AdditionalService => 'Additional Service',
            self::Other => 'Other',
        };
    }
}
