<?php

namespace App\Services;

use App\Enums\AttendanceAlertMode;
use App\Models\CommunicationSetting;
use App\Models\School;

/**
 * A school's alert switches. Reading never writes a row: a school that has
 * never opened the settings screen gets the configured defaults.
 */
class CommunicationSettingService
{
    public function for(int $schoolId): CommunicationSetting
    {
        $defaults = config('communication.defaults');

        return CommunicationSetting::query()->firstOrNew(
            ['school_id' => $schoolId],
            [
                'sms_enabled' => $defaults['sms_enabled'],
                'attendance_alerts' => $defaults['attendance_alerts'],
                'transport_alerts_enabled' => $defaults['transport_alerts_enabled'],
                'leave_alerts_enabled' => $defaults['leave_alerts_enabled'],
                'provider' => config('communication.default'),
                'sender_id' => $defaults['sender_id'],
            ],
        );
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(School $school, array $data): CommunicationSetting
    {
        $setting = $this->for($school->id);

        $setting->fill([
            'sms_enabled' => $data['sms_enabled'] ?? $setting->sms_enabled,
            'attendance_alerts' => $data['attendance_alerts'] ?? $setting->attendance_alerts,
            'transport_alerts_enabled' => $data['transport_alerts_enabled'] ?? $setting->transport_alerts_enabled,
            'leave_alerts_enabled' => $data['leave_alerts_enabled'] ?? $setting->leave_alerts_enabled,
            'provider' => $data['provider'] ?? $setting->provider,
            'sender_id' => array_key_exists('sender_id', $data) ? $data['sender_id'] : $setting->sender_id,
        ]);
        $setting->school_id = $school->id;
        $setting->save();

        return $setting->refresh();
    }

    public function attendanceMode(int $schoolId): AttendanceAlertMode
    {
        return $this->for($schoolId)->attendance_alerts;
    }
}
