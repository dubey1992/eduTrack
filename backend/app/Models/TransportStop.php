<?php

namespace App\Models;

use Database\Factories\TransportStopFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['school_id', 'route_id', 'name', 'sequence_number', 'pickup_time', 'drop_time'])]
class TransportStop extends Model
{
    /** @use HasFactory<TransportStopFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'sequence_number' => 'integer',
        ];
    }

    /**
     * @return BelongsTo<TransportRoute, $this>
     */
    public function route(): BelongsTo
    {
        return $this->belongsTo(TransportRoute::class, 'route_id');
    }

    /**
     * @return HasMany<StudentTransportAssignment, $this>
     */
    public function assignments(): HasMany
    {
        return $this->hasMany(StudentTransportAssignment::class, 'transport_stop_id');
    }
}
