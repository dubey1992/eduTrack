<?php

namespace App\Http\Requests\Transport;

use App\Enums\TripDirection;
use App\Http\Requests\Concerns\ScopesSchool;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class StartTripRequest extends FormRequest
{
    use ScopesSchool;

    /**
     * TransportTripPolicy::create is checked in the controller once the
     * route is loaded (a bad id is a 422, not a 403).
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $actor = $this->user();

        return [
            'route_id' => [
                'required', 'integer',
                Rule::exists('transport_routes', 'id')->where(
                    fn ($query) => $this->schoolScope()->applyTo($query)
                ),
            ],
            'direction' => ['required', new Enum(TripDirection::class)],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return ['route_id.exists' => 'The selected route does not belong to this school.'];
    }
}
