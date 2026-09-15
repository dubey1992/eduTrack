{{--
    What `php artisan down` shows the world.

    Set MAINTENANCE_UNTIL in .env before taking the platform down and this
    says when to come back; leave it unset and it says less rather than
    promising something nobody can keep. See App\Support\MaintenanceWindow.
--}}
@extends('errors.layout')

@section('title', 'Scheduled maintenance')

@php
    $endsAt = \App\Support\MaintenanceWindow::endsAtLabel();
@endphp

@section('content')
    <span class="badge">Scheduled maintenance</span>

    <h1>We're making School365ai better.</h1>

    <p>
        The platform is briefly offline while we finish some planned work.
        Nothing has been lost - attendance, records and messages are all
        exactly where you left them, and will be there when we're back.
    </p>

    @if ($endsAt)
        <p>
            We expect to be back by <strong>{{ $endsAt }}</strong>.
        </p>
    @else
        <p>
            We expect to be back shortly. Please try again in a few minutes.
        </p>
    @endif

    <div class="actions">
        <a class="button button-primary" href="{{ url()->current() }}">Try again</a>
    </div>

    <p class="detail">
        If this is urgent, contact your school administrator - they have a
        direct line to our support team.
    </p>
@endsection
