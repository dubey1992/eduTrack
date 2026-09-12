<?php

namespace App\Models;

use App\Enums\AttendanceAlertMode;
use Database\Factories\CommunicationSettingFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'school_id',
    'sms_enabled',
    'attendance_alerts',
    'transport_alerts_enabled',
    'leave_alerts_enabled',
    'provider',
    'sender_id',
])]
class CommunicationSetting extends Model
{
    /** @use HasFactory<CommunicationSettingFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'sms_enabled' => 'boolean',
            'attendance_alerts' => AttendanceAlertMode::class,
            'transport_alerts_enabled' => 'boolean',
            'leave_alerts_enabled' => 'boolean',
        ];
    }

    /**
     * @return BelongsTo<School, $this>
     */
    public function school(): BelongsTo
    {
        return $this->belongsTo(School::class);
    }
}
