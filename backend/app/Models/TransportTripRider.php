<?php

namespace App\Models;

use App\Enums\TripRiderStatus;
use Database\Factories\TransportTripRiderFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['trip_id', 'student_id', 'stop_id', 'stop_name', 'stop_sequence_number', 'status', 'boarded_at', 'dropped_at'])]
class TransportTripRider extends Model
{
    /** @use HasFactory<TransportTripRiderFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'stop_sequence_number' => 'integer',
            'status' => TripRiderStatus::class,
            'boarded_at' => 'datetime',
            'dropped_at' => 'datetime',
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
     * @return BelongsTo<Student, $this>
     */
    public function student(): BelongsTo
    {
        return $this->belongsTo(Student::class);
    }

    /**
     * @return BelongsTo<TransportStop, $this>
     */
    public function stop(): BelongsTo
    {
        return $this->belongsTo(TransportStop::class, 'stop_id');
    }
}
