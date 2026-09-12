<?php

namespace App\Support;

/**
 * Fills {token} placeholders in a message body. Tokens the caller did not
 * supply are blanked rather than left as literal braces, so a reworded
 * template can never leak "{student_name}" into a parent's SMS.
 */
class TemplateRenderer
{
    /**
     * @param  array<string, string|null>  $tokens
     */
    public function render(string $body, array $tokens): string
    {
        $filled = preg_replace_callback(
            '/\{([a-z_]+)\}/',
            fn (array $match) => (string) ($tokens[$match[1]] ?? ''),
            $body,
        ) ?? $body;

        return trim(preg_replace('/[ \t]{2,}/', ' ', $filled) ?? $filled);
    }

    /**
     * The tokens used in a body that the given event does not provide.
     *
     * @param  array<int, string>  $allowed
     * @return array<int, string>
     */
    public function unknownTokens(string $body, array $allowed): array
    {
        preg_match_all('/\{([a-z_]+)\}/', $body, $matches);

        return array_values(array_unique(array_diff($matches[1], $allowed)));
    }
}
