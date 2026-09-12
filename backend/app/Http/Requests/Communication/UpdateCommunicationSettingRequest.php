<?php

namespace App\Http\Requests\Communication;

use App\Enums\AttendanceAlertMode;
use App\Models\Message;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class UpdateCommunicationSettingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('configure', [Message::class, $this->schoolId()]);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'school_id' => ['nullable', 'integer', 'exists:schools,id'],
            'sms_enabled' => ['required', 'boolean'],
            'attendance_alerts' => ['required', new Enum(AttendanceAlertMode::class)],
            'transport_alerts_enabled' => ['required', 'boolean'],
            'leave_alerts_enabled' => ['required', 'boolean'],
            'provider' => ['required', 'string', Rule::in(array_keys(config('communication.gateways')))],
            'sender_id' => ['nullable', 'string', 'max:20', 'regex:/^[A-Za-z0-9-]+$/'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'sender_id.regex' => 'A sender ID can only contain letters, numbers and hyphens.',
            'provider.in' => 'That SMS gateway is not available.',
        ];
    }

    public function schoolId(): ?int
    {
        $requested = $this->input('school_id');

        return $requested === null ? $this->user()->school_id : (int) $requested;
    }
}
