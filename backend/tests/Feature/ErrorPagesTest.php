<?php

namespace Tests\Feature;

use App\Exceptions\ApiExceptionRenderer;
use App\Support\MaintenanceWindow;
use Symfony\Component\HttpKernel\Exception\ServiceUnavailableHttpException;
use Tests\TestCase;

/**
 * The pages people meet when something is not normal.
 *
 * Two audiences, and they must not be confused: a browser gets a page it can
 * read, and the API gets JSON the Flutter client can act on. The rule that
 * matters most is the last group - an error page must never leak what went
 * wrong internally.
 */
class ErrorPagesTest extends TestCase
{
    // ── 404, in a browser ───────────────────────────────────────────────

    public function test_a_browser_asking_for_a_path_that_does_not_exist_gets_the_custom_page(): void
    {
        $response = $this->get('/no-such-page');

        $response->assertNotFound()
            ->assertSee("We couldn't find that page.", false)
            ->assertSee('Error 404')
            // Branded, so it reads as School365ai rather than as a bare server
            // error - which is the whole point of a custom page.
            ->assertSee('School365ai')
            ->assertSee('Smarter Schools. Brighter Futures.');
    }

    public function test_the_404_page_shows_the_path_that_was_asked_for(): void
    {
        $this->get('/studnets')->assertNotFound()->assertSee('/studnets');
    }

    public function test_the_404_page_points_back_at_the_app(): void
    {
        config(['app.frontend_url' => 'https://app.school365ai.test']);

        $this->get('/no-such-page')
            ->assertNotFound()
            ->assertSee('https://app.school365ai.test', false)
            ->assertSee('https://app.school365ai.test/#/login', false);
    }

    public function test_the_404_page_asks_not_to_be_indexed(): void
    {
        // A 404 in search results is worse than no result at all.
        $this->get('/no-such-page')->assertSee('name="robots" content="noindex"', false);
    }

    // ── 404, on the API ─────────────────────────────────────────────────

    public function test_the_api_still_answers_a_missing_route_with_json(): void
    {
        $this->getJson('/api/v1/no-such-endpoint')
            ->assertNotFound()
            ->assertJsonPath('code', 'NOT_FOUND')
            ->assertJsonPath('message', 'The requested resource was not found.');
    }

    // ── scheduled maintenance ───────────────────────────────────────────

    public function test_the_maintenance_page_says_what_is_happening_and_that_nothing_was_lost(): void
    {
        // Rendered directly rather than by taking the app down: `artisan down`
        // inside a test run would take the test run with it.
        $rendered = view('errors.503')->render();

        $this->assertStringContainsString('Scheduled maintenance', $rendered);
        $this->assertStringContainsString("We're making School365ai better.", $rendered);
        $this->assertStringContainsString('Nothing has been lost', $rendered);
        $this->assertStringContainsString('School365ai', $rendered);
        $this->assertStringContainsString('Try again', $rendered);
    }

    public function test_the_maintenance_page_names_the_time_it_expects_to_be_back(): void
    {
        config([
            'app.maintenance_until' => now()->addHours(3)->format('Y-m-d H:i'),
            'app.platform_timezone' => 'UTC',
        ]);

        $rendered = view('errors.503')->render();

        $this->assertStringContainsString('We expect to be back by', $rendered);
        $this->assertStringContainsString(MaintenanceWindow::endsAtLabel(), $rendered);
        $this->assertStringNotContainsString('back shortly. Please try again', $rendered);
    }

    public function test_the_maintenance_page_says_less_when_no_time_is_set(): void
    {
        config(['app.maintenance_until' => null]);

        $rendered = view('errors.503')->render();

        $this->assertStringContainsString('back shortly', $rendered);
        $this->assertStringNotContainsString('We expect to be back by', $rendered);
    }

    // ── the window itself ───────────────────────────────────────────────

    public function test_the_window_reads_a_time_in_the_platform_timezone_and_us_format(): void
    {
        config([
            'app.maintenance_until' => '2099-09-15 18:30',
            'app.platform_timezone' => 'UTC',
        ]);

        $this->assertSame('09/15/2099 6:30 PM UTC', MaintenanceWindow::endsAtLabel());
    }

    public function test_a_window_left_over_from_last_time_is_ignored(): void
    {
        // A stale value would otherwise promise a return time in the past,
        // which reads as broken rather than as running late.
        config(['app.maintenance_until' => '2020-01-01 09:00']);

        $this->assertNull(MaintenanceWindow::endsAtLabel());
    }

    public function test_a_window_that_is_not_a_time_is_ignored_rather_than_shown(): void
    {
        config(['app.maintenance_until' => 'soon-ish']);

        $this->assertNull(MaintenanceWindow::endsAtLabel());
    }

    public function test_no_window_set_is_not_an_error(): void
    {
        config(['app.maintenance_until' => null]);
        $this->assertNull(MaintenanceWindow::endsAtLabel());

        config(['app.maintenance_until' => '   ']);
        $this->assertNull(MaintenanceWindow::endsAtLabel());
    }

    // ── what the client is told ─────────────────────────────────────────

    public function test_the_api_gives_maintenance_its_own_code_so_the_client_can_act_on_it(): void
    {
        // A generic HTTP_ERROR would leave the app unable to tell a
        // maintenance window from any other failure, and it has to: a window
        // means every screen is down, not just the one in use.
        $response = ApiExceptionRenderer::render(new ServiceUnavailableHttpException, request());

        $this->assertSame(503, $response->getStatusCode());
        $this->assertSame('SERVICE_UNAVAILABLE', $response->getData()->code);
        $this->assertStringContainsString('scheduled maintenance', $response->getData()->message);
    }

    // ── nothing leaks ───────────────────────────────────────────────────

    public function test_an_error_page_never_shows_the_framework_behind_it(): void
    {
        $body = $this->get('/no-such-page')->getContent();

        foreach (['Laravel', 'Symfony', 'Exception', 'vendor/', 'Stack trace'] as $leak) {
            $this->assertStringNotContainsString($leak, $body, "The 404 page leaked \"{$leak}\".");
        }
    }

    public function test_an_error_page_needs_nothing_from_the_internet_to_render(): void
    {
        // A maintenance page that fetches a font or a stylesheet from
        // somewhere else is a page that breaks exactly when it is needed.
        foreach ([$this->get('/no-such-page')->getContent(), view('errors.503')->render()] as $body) {
            $this->assertStringNotContainsString('https://fonts.', $body);
            $this->assertStringNotContainsString('cdn.', $body);
            $this->assertStringNotContainsString('<script', $body);
        }
    }
}
