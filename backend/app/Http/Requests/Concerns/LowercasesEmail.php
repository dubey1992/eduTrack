<?php

namespace App\Http\Requests\Concerns;

use Illuminate\Support\Str;

/**
 * Lowercases the `email` field before anything looks at it.
 *
 * The User model stores addresses lowercase, so validation has to ask about
 * them in the same form: a `unique` rule given "Head@school.test" would look
 * for exactly that and find nothing, and the insert would then be refused by
 * the index instead - a 500 where a field-level 422 belongs. Signing in has
 * the same problem in reverse, where the lookup simply fails and the person is
 * told their password is wrong.
 *
 * Why here rather than a rule: it has to happen before validation runs, and it
 * has to apply to the value that reaches the database, not merely to the one
 * that gets checked.
 */
trait LowercasesEmail
{
    protected function prepareForValidation(): void
    {
        $email = $this->input('email');

        if (is_string($email)) {
            $this->merge(['email' => Str::lower(trim($email))]);
        }
    }
}
