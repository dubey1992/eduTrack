<?php

namespace Database\Factories;

use App\Enums\AttendanceAlertMode;
use App\Models\CommunicationSetting;
use App\Models\School;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<CommunicationSetting>
 */
class CommunicationSettingFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'sms_enabled' => true,
            'attendance_alerts' => AttendanceAlertMode::AbsentOnly,
            'transport_alerts_enabled' => true,
            'leave_alerts_enabled' => true,
            'provider' => 'log',
            'sender_id' => null,
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function smsOff(): static
    {
        return $this->state(fn (array $attributes) => ['sms_enabled' => false]);
    }

    public function attendanceAlerts(AttendanceAlertMode $mode): static
    {
        return $this->state(fn (array $attributes) => ['attendance_alerts' => $mode]);
    }
}
