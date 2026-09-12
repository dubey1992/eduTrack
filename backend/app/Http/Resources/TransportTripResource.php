<?php

namespace App\Http\Resources;

use App\Enums\TripEventType;
use App\Enums\TripRiderStatus;
use App\Http\Resources\Concerns\RendersSchoolTime;
use App\Models\TransportTrip;
use App\Models\TransportTripEvent;
use App\Models\TransportTripRider;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Collection;

/**
 * A trip with its live figures. Counts and the stops-left number are only
 * present when the riders / route stops were loaded (the detail view);
 * the list carries `riders_count` instead.
 *
 * @mixin TransportTrip
 */
class TransportTripResource extends JsonResource
{
    use RendersSchoolTime;

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'school_id' => $this->school_id,
            'route_id' => $this->route_id,
            'route_name' => $this->route->name,
            'route_label' => "{$this->vehicle->name} - {$this->route->name}",
            'vehicle_id' => $this->vehicle_id,
            'vehicle_name' => $this->vehicle->name,
            'vehicle_registration_number' => $this->vehicle->registration_number,
            'driver_id' => $this->driver_id,
            'driver_name' => $this->driver->name,
            'driver_mobile' => $this->driver->mobile,
            'trip_date' => $this->trip_date->toDateString(),
            'direction' => $this->direction->value,
            'status' => $this->status->value,
            'current_stop_id' => $this->current_stop_id,
            'current_stop_name' => $this->currentStop?->name,
            'started_by_name' => $this->whenLoaded('startedBy', fn () => $this->startedBy->name),
            'started_at' => $this->started_at,
            'ended_at' => $this->ended_at,
            // Rendered here because the client has no timezone database; the
            // school's own clock is the only one that makes sense on a trip.
            'started_at_label' => $this->timeLabel($this->started_at),
            'ended_at_label' => $this->timeLabel($this->ended_at),
            'timezone' => $this->clock()->timezone(),
            // From withCount() on the list, from the loaded riders on the detail.
            'riders_count' => $this->relationLoaded('riders') ? $this->riders->count() : $this->riders_count,
            $this->mergeWhen($this->relationLoaded('riders'), fn () => $this->riderCounts()),
            'stops_left' => $this->when(
                $this->relationLoaded('route') && $this->route->relationLoaded('stops'),
                fn () => $this->stopsLeft()
            ),
            // Riders and events share the trip's school, so they are handed
            // the clock rather than each resolving it again.
            'riders' => $this->when(
                $this->relationLoaded('riders'),
                fn () => $this->riders
                    ->map(fn ($rider) => (new TripRiderResource($rider))->usingClock($this->clock()))
                    ->values()
            ),
            'events' => $this->when(
                $this->relationLoaded('events'),
                fn () => $this->events
                    ->map(fn ($event) => (new TripEventResource($event))->usingClock($this->clock()))
                    ->values()
            ),
            'stops' => $this->when(
                $this->relationLoaded('route') && $this->route->relationLoaded('stops'),
                fn () => $this->route->stops->map(fn ($stop) => [
                    'id' => $stop->id,
                    'name' => $stop->name,
                    'sequence_number' => $stop->sequence_number,
                    'pickup_time' => $stop->pickup_time === null ? null : substr($stop->pickup_time, 0, 5),
                    'drop_time' => $stop->drop_time === null ? null : substr($stop->drop_time, 0, 5),
                    'reached' => $this->reachedStopIds()->contains($stop->id),
                ])->values()->all()
            ),
        ];
    }

    /**
     * @return array<string, int>
     */
    private function riderCounts(): array
    {
        $byStatus = $this->riders->countBy(fn (TransportTripRider $rider) => $rider->status->value);

        return [
            'pending_count' => $byStatus->get(TripRiderStatus::Pending->value, 0),
            'boarded_count' => $byStatus->get(TripRiderStatus::Boarded->value, 0),
            'dropped_count' => $byStatus->get(TripRiderStatus::Dropped->value, 0),
            'absent_count' => $byStatus->get(TripRiderStatus::Absent->value, 0),
        ];
    }

    private function stopsLeft(): int
    {
        $reached = $this->reachedStopIds();

        return $this->route->stops->reject(fn ($stop) => $reached->contains($stop->id))->count();
    }

    /**
     * @return Collection<int, int>
     */
    private function reachedStopIds(): Collection
    {
        if (! $this->relationLoaded('events')) {
            return collect($this->current_stop_id === null ? [] : [$this->current_stop_id]);
        }

        return $this->events
            ->filter(fn (TransportTripEvent $event) => $event->type === TripEventType::StopReached && $event->stop_id !== null)
            ->pluck('stop_id')
            ->unique()
            ->values();
    }
}
