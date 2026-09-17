<?php

namespace App\Models;

use App\Enums\TripDirection;
use App\Enums\TripStatus;
use Database\Factories\TransportTripFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'school_id', 'route_id', 'vehicle_id', 'driver_id', 'trip_date', 'direction', 'status',
    'current_stop_id', 'started_by', 'started_at', 'ended_at',
])]
class TransportTrip extends Model
{
    /** @use HasFactory<TransportTripFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'trip_date' => 'date',
            'direction' => TripDirection::class,
            'status' => TripStatus::class,
            'started_at' => 'datetime',
            'ended_at' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<School, $this>
     */
    public function school(): BelongsTo
    {
        return $this->belongsTo(School::class);
    }

    /**
     * @return BelongsTo<TransportRoute, $this>
     */
    public function route(): BelongsTo
    {
        return $this->belongsTo(TransportRoute::class, 'route_id');
    }

    /**
     * @return BelongsTo<Vehicle, $this>
     */
    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(Vehicle::class);
    }

    /**
     * @return BelongsTo<Driver, $this>
     */
    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * @return BelongsTo<TransportStop, $this>
     */
    public function currentStop(): BelongsTo
    {
        return $this->belongsTo(TransportStop::class, 'current_stop_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function startedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'started_by');
    }

    /**
     * @return HasMany<TransportTripRider, $this>
     */
    public function riders(): HasMany
    {
        // A stop has many riders; id keeps the ones at the same stop in a
        // fixed order from one read of the trip to the next.
        return $this->hasMany(TransportTripRider::class, 'trip_id')->orderBy('stop_sequence_number')->orderBy('id');
    }

    /**
     * @return HasMany<TransportTripEvent, $this>
     */
    public function events(): HasMany
    {
        return $this->hasMany(TransportTripEvent::class, 'trip_id')->orderBy('recorded_at')->orderBy('id');
    }

    public function isInProgress(): bool
    {
        return $this->status === TripStatus::InProgress;
    }
}
