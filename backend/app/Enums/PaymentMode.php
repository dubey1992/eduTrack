<?php

namespace App\Enums;

enum PaymentMode: string
{
    case Cash = 'cash';
    case BankTransfer = 'bank_transfer';
    case Upi = 'upi';
    case Cheque = 'cheque';
    case Online = 'online';
}
