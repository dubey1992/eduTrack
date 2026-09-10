<?php

namespace App\Models;

use Database\Factories\StudentTransportAssignmentFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['school_id', 'student_id', 'route_id', 'transport_stop_id'])]
class StudentTransportAssignment extends Model
{
    /** @use HasFactory<StudentTransportAssignmentFactory> */
    use HasFactory;

    /**
     * @return BelongsTo<Student, $this>
     */
    public function student(): BelongsTo
    {
        return $this->belongsTo(Student::class);
    }

    /**
     * @return BelongsTo<TransportRoute, $this>
     */
    public function route(): BelongsTo
    {
        return $this->belongsTo(TransportRoute::class, 'route_id');
    }

    /**
     * @return BelongsTo<TransportStop, $this>
     */
    public function stop(): BelongsTo
    {
        return $this->belongsTo(TransportStop::class, 'transport_stop_id');
    }
}
