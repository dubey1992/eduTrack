<?php

namespace App\Models;

use App\Enums\TransportStatus;
use Database\Factories\TransportRouteFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['school_id', 'name', 'vehicle_id', 'driver_id', 'status'])]
class TransportRoute extends Model
{
    /** @use HasFactory<TransportRouteFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'status' => TransportStatus::class,
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
     * @return HasMany<TransportStop, $this>
     */
    public function stops(): HasMany
    {
        return $this->hasMany(TransportStop::class, 'route_id')->orderBy('sequence_number');
    }

    /**
     * @return HasMany<StudentTransportAssignment, $this>
     */
    public function assignments(): HasMany
    {
        return $this->hasMany(StudentTransportAssignment::class, 'route_id');
    }

    /**
     * @return HasMany<TransportTrip, $this>
     */
    public function trips(): HasMany
    {
        return $this->hasMany(TransportTrip::class, 'route_id');
    }

    public function isActive(): bool
    {
        return $this->status === TransportStatus::Active;
    }

    /**
     * "Bus 04 - Green Park" when a vehicle is attached, else just the name -
     * the label the prototype uses everywhere a route is picked.
     */
    public function label(): string
    {
        return $this->vehicle === null ? $this->name : "{$this->vehicle->name} - {$this->name}";
    }
}
