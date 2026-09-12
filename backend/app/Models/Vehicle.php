<?php

namespace App\Models;

use App\Enums\TransportStatus;
use Database\Factories\VehicleFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

#[Fillable(['school_id', 'name', 'registration_number', 'capacity', 'status'])]
class Vehicle extends Model
{
    /** @use HasFactory<VehicleFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'capacity' => 'integer',
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
     * The route this vehicle currently serves, if any.
     *
     * @return HasOne<TransportRoute, $this>
     */
    public function route(): HasOne
    {
        return $this->hasOne(TransportRoute::class);
    }

    /**
     * @return HasMany<TransportTrip, $this>
     */
    public function trips(): HasMany
    {
        return $this->hasMany(TransportTrip::class);
    }
}
