<?php

return [

    /*
    |--------------------------------------------------------------------------
    | SMS gateway
    |--------------------------------------------------------------------------
    |
    | Which adapter sends SMS. "log" is the prototype's "Demo Gateway": it
    | records the message and writes it to the log file without calling any
    | third party, which is what local development and the test suite use.
    | A school can pick a different gateway in its communication settings,
    | provided that gateway is listed here.
    |
    */

    'default' => env('SMS_GATEWAY', 'log'),

    'gateways' => [
        'log' => [
            'driver' => 'log',
            'label' => 'Demo Gateway',
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Defaults for a school that has not saved its settings yet
    |--------------------------------------------------------------------------
    */

    'defaults' => [
        'sms_enabled' => true,
        'attendance_alerts' => 'absent',
        'transport_alerts_enabled' => true,
        'leave_alerts_enabled' => true,
        'sender_id' => null,
    ],

    /*
    |--------------------------------------------------------------------------
    | Message body limit
    |--------------------------------------------------------------------------
    |
    | Three 160-character SMS segments. Templates are validated against this
    | before they are saved, using the longest plausible token values.
    |
    */

    'max_body_length' => 480,

];
