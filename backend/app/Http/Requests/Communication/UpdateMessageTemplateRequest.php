<?php

namespace App\Http\Requests\Communication;

use App\Enums\MessageEvent;
use App\Models\Message;
use App\Support\TemplateRenderer;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Response;

class UpdateMessageTemplateRequest extends FormRequest
{
    /**
     * An event that does not exist is a missing address, not a bad body, so
     * it must answer 404 whatever the body says.
     */
    protected function prepareForValidation(): void
    {
        abort_if($this->event() === null, Response::HTTP_NOT_FOUND);
    }

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
            'body' => [
                'required',
                'string',
                'min:10',
                'max:'.config('communication.max_body_length'),
                function (string $attribute, mixed $value, Closure $fail) {
                    $event = $this->event();

                    if ($event === null) {
                        return;
                    }

                    $unknown = app(TemplateRenderer::class)->unknownTokens((string) $value, $event->tokens());

                    if ($unknown !== []) {
                        $fail(sprintf(
                            'This message can only use these placeholders: %s. Remove %s.',
                            '{'.implode('}, {', $event->tokens()).'}',
                            '{'.implode('}, {', $unknown).'}',
                        ));
                    }
                },
            ],
        ];
    }

    public function event(): ?MessageEvent
    {
        return MessageEvent::tryFrom((string) $this->route('event'));
    }

    public function schoolId(): ?int
    {
        $requested = $this->input('school_id');

        return $requested === null ? $this->user()->school_id : (int) $requested;
    }
}
