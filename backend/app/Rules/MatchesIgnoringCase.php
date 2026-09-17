<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * `exists` or `unique`, comparing a column the way a person reads it.
 *
 * For the spreadsheet importers, where a department is typed "science" and a
 * teacher's address "Priya.Nair@…": the importers already look those up
 * case-blind, so validation has to agree with them. Laravel's own rules
 * compare with `=`, which MySQL's collation happens to make case-blind and
 * PostgreSQL does not - a file that imported on one engine would be refused
 * on the other, or (for `unique` on an address stored lowercase) pass
 * validation and then fail on the unique index halfway through the import.
 */
class MatchesIgnoringCase implements ValidationRule
{
    /**
     * @param  Builder<Model>  $query  already narrowed to the school, role and so on
     */
    private function __construct(
        private readonly Builder $query,
        private readonly string $column,
        private readonly bool $mustExist,
    ) {}

    /**
     * @param  Builder<Model>  $query
     */
    public static function exists(Builder $query, string $column): self
    {
        return new self($query, $column, true);
    }

    /**
     * @param  Builder<Model>  $query
     */
    public static function unique(Builder $query, string $column): self
    {
        return new self($query, $column, false);
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_string($value) || trim($value) === '') {
            return;
        }

        // The column name comes from code, never from the request.
        $found = (clone $this->query)
            ->whereRaw("LOWER({$this->column}) = ?", [mb_strtolower(trim($value))])
            ->exists();

        if ($this->mustExist && ! $found) {
            $fail('validation.exists')->translate();
        }

        if (! $this->mustExist && $found) {
            $fail('validation.unique')->translate();
        }
    }
}
