<?php

namespace App\Models;

use App\Enums\TripEventType;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'school_id', 'trip_id', 'type', 'stop_id', 'stop_name', 'student_id', 'student_name',
    'recorded_by', 'recorded_at', 'note',
])]
class TransportTripEvent extends Model
{
    protected function casts(): array
    {
        return [
            'type' => TripEventType::class,
            'recorded_at' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<TransportTrip, $this>
     */
    public function trip(): BelongsTo
    {
        return $this->belongsTo(TransportTrip::class, 'trip_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function recordedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recorded_by');
    }
}
