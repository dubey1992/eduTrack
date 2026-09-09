<?php

namespace App\Models;

use Database\Factories\DailyTeachingReportFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'school_id', 'timetable_entry_id', 'teacher_id', 'report_date',
    'topic_taught', 'homework', 'remarks', 'reviewed_by', 'reviewed_at',
])]
class DailyTeachingReport extends Model
{
    /** @use HasFactory<DailyTeachingReportFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'report_date' => 'date',
            'reviewed_at' => 'datetime',
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
     * @return BelongsTo<TimetableEntry, $this>
     */
    public function timetableEntry(): BelongsTo
    {
        return $this->belongsTo(TimetableEntry::class);
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function teacher(): BelongsTo
    {
        return $this->belongsTo(User::class, 'teacher_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function reviewedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }
}
