<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Route;
use Tests\TestCase;

/**
 * The contract suite's manifest still lists every route this API serves.
 *
 * `contract/endpoints.py` is what makes "the contract covers the API" a fact
 * rather than a feeling, and a manifest that quietly falls behind the routes is
 * worse than none at all - it reports coverage of an API that no longer exists.
 *
 * So adding an endpoint fails this test until it is listed, which forces a
 * decision about covering it rather than letting it slip in unnoticed. That
 * matters most during the Python rewrite (docs/python-migration.md), when the
 * manifest is the definition of how much is left to do.
 *
 * It reads a Python file from PHP, which is odd-looking and deliberate: the
 * manifest belongs with the contract suite, because the Python backend will owe
 * exactly the same list. Only this check needs to live here, because only here
 * are the real routes knowable.
 */
class RouteManifestTest extends TestCase
{
    private const MANIFEST = __DIR__.'/../../../contract/endpoints.py';

    public function test_every_route_is_listed_in_the_contract_manifest(): void
    {
        $manifest = $this->manifest();
        $missing = array_values(array_diff($this->routes(), $manifest));

        $this->assertSame(
            [],
            $missing,
            "These endpoints are not in contract/endpoints.py, so the contract suite does not\n".
            "know they exist and nobody has decided whether to cover them:\n  ".
            implode("\n  ", $missing)."\n",
        );
    }

    public function test_the_manifest_lists_nothing_that_has_gone(): void
    {
        // The other direction, and the one that rots quietly: an endpoint
        // removed from the API but left in the manifest makes the coverage
        // figure describe work that no longer needs doing.
        $stale = array_values(array_diff($this->manifest(), $this->routes()));

        $this->assertSame(
            [],
            $stale,
            "contract/endpoints.py lists endpoints this API no longer serves:\n  ".
            implode("\n  ", $stale)."\n",
        );
    }

    /**
     * @return array<int, string>
     */
    private function routes(): array
    {
        $found = [];

        foreach (Route::getRoutes() as $route) {
            $uri = $route->uri();

            if (! str_starts_with($uri, 'api/v1/')) {
                continue;
            }

            foreach ($route->methods() as $method) {
                if (in_array($method, ['HEAD', 'OPTIONS'], true)) {
                    continue;
                }

                $found[] = $method.' '.str_replace('api/v1/', '', $uri);
            }
        }

        sort($found);

        return array_values(array_unique($found));
    }

    /**
     * @return array<int, string>
     */
    private function manifest(): array
    {
        $path = self::MANIFEST;

        $this->assertFileExists($path, 'The contract suite\'s endpoint manifest is missing.');

        // Each entry is a ("METHOD", "uri") tuple on its own line. Parsed with
        // a regex rather than by running Python, so this test needs nothing
        // installed beyond PHP.
        preg_match_all('/\("([A-Z]+)",\s*"([^"]+)"\)/', (string) file_get_contents($path), $matches, PREG_SET_ORDER);

        $listed = array_map(fn (array $m) => $m[1].' '.$m[2], $matches);
        sort($listed);

        return array_values(array_unique($listed));
    }
}
