<?php

namespace App\Http\Resources;

use App\Models\CommunicationSetting;
use App\Support\Sms\SmsGatewayManager;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin CommunicationSetting
 */
class CommunicationSettingResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $gateways = app(SmsGatewayManager::class);

        return [
            'school_id' => $this->school_id,
            'sms_enabled' => $this->sms_enabled,
            'attendance_alerts' => $this->attendance_alerts->value,
            'attendance_alerts_label' => $this->attendance_alerts->label(),
            'transport_alerts_enabled' => $this->transport_alerts_enabled,
            'leave_alerts_enabled' => $this->leave_alerts_enabled,
            'provider' => $this->provider,
            'provider_label' => $gateways->label($this->provider),
            'sender_id' => $this->sender_id,
            'available_providers' => collect(config('communication.gateways'))
                ->map(fn (array $gateway, string $key) => ['value' => $key, 'label' => $gateway['label']])
                ->values(),
            'is_saved' => $this->exists,
        ];
    }
}
