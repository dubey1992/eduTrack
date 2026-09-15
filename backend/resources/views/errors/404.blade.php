{{--
    A browser asking this host for a path that does not exist.

    Mostly a mistyped URL or a stale bookmark - the app's own unknown routes
    are handled inside Flutter (NotFoundScreen), which keeps the sidebar and
    the session. This is the one people reach from outside.
--}}
@extends('errors.layout')

@section('title', 'Page not found')

@section('content')
    <span class="badge">Error 404</span>

    <h1>We couldn't find that page.</h1>

    <p>
        The link may be out of date, or the address may have a typo in it.
        Nothing has gone wrong with your account, and nothing has been lost.
    </p>

    <div class="actions">
        <a class="button button-primary" href="{{ config('app.frontend_url') }}">Go to School365ai</a>
        <a class="button button-secondary" href="{{ rtrim(config('app.frontend_url'), '/') }}/#/login">Sign in</a>
    </div>

    @if (request()->path() !== '/')
        <p class="detail">
            You asked for <code>/{{ request()->path() }}</code>
        </p>
    @endif
@endsection
