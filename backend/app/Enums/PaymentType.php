<?php

namespace App\Enums;

enum PaymentType: string
{
    case SetupFee = 'setup_fee';
    case AnnualMaintenance = 'annual_maintenance';
    case AdditionalService = 'additional_service';
    case Other = 'other';
}
