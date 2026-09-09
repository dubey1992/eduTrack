<?php

namespace App\Models;

use Database\Factories\SyllabusTopicFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['school_id', 'subject_id', 'title', 'sequence_number'])]
class SyllabusTopic extends Model
{
    /** @use HasFactory<SyllabusTopicFactory> */
    use HasFactory;

    /**
     * @return BelongsTo<School, $this>
     */
    public function school(): BelongsTo
    {
        return $this->belongsTo(School::class);
    }

    /**
     * @return BelongsTo<Subject, $this>
     */
    public function subject(): BelongsTo
    {
        return $this->belongsTo(Subject::class);
    }

    /**
     * @return HasMany<SyllabusTopicProgress, $this>
     */
    public function progress(): HasMany
    {
        return $this->hasMany(SyllabusTopicProgress::class);
    }
}
