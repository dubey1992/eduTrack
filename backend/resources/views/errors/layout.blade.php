{{--
    The shell every error page shares.

    Deliberately self-contained: no stylesheet, no font and no script loaded
    from anywhere else. A maintenance page that needs the app it is standing
    in for, or a 404 that needs a CDN, is a page that fails exactly when it is
    needed. Everything here is inline and works offline.
--}}
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>@yield('title') - School365ai</title>
    <link rel="icon" type="image/png" href="{{ asset('favicon.png') }}">
    <style>
        :root {
            --ink: #0F172A;
            --body: #334155;
            --muted: #64748B;
            --ground: #F8FAFC;
            --surface: #FFFFFF;
            --border: #E2E8F0;
            --accent: #2563EB;
            --accent-dark: #1D4ED8;
            --accent-tint: #EFF6FF;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --ink: #F1F5F9;
                --body: #CBD5E1;
                --muted: #94A3B8;
                --ground: #0B0F1A;
                --surface: #111827;
                --border: #263042;
                --accent: #60A5FA;
                --accent-dark: #3B82F6;
                --accent-tint: #172034;
            }
        }

        * { box-sizing: border-box; }

        body {
            margin: 0;
            padding: 32px 20px;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: var(--ground);
            color: var(--body);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                         "Helvetica Neue", Arial, sans-serif;
            font-size: 16px;
            line-height: 1.6;
            -webkit-font-smoothing: antialiased;
        }

        .page { width: 100%; max-width: 560px; }

        .brand {
            display: flex;
            align-items: center;
            gap: 12px;
            margin-bottom: 28px;
        }

        .brand-mark {
            width: 44px;
            height: 44px;
            flex: 0 0 44px;
            border-radius: 12px;
            background: var(--accent);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 22px;
            line-height: 1;
        }

        .brand-name {
            font-size: 19px;
            font-weight: 700;
            color: var(--ink);
            letter-spacing: -0.01em;
        }

        .brand-tagline {
            font-size: 13px;
            color: var(--muted);
        }

        .card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 40px 36px;
        }

        .badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 6px 12px;
            border-radius: 999px;
            background: var(--accent-tint);
            color: var(--accent-dark);
            font-size: 13px;
            font-weight: 600;
            letter-spacing: 0.01em;
        }

        h1 {
            margin: 20px 0 12px;
            font-size: 30px;
            line-height: 1.2;
            font-weight: 700;
            color: var(--ink);
            letter-spacing: -0.02em;
        }

        p { margin: 0 0 14px; }
        p:last-of-type { margin-bottom: 0; }

        .actions {
            display: flex;
            flex-wrap: wrap;
            gap: 12px;
            margin-top: 28px;
        }

        .button {
            display: inline-block;
            padding: 12px 22px;
            border-radius: 10px;
            font-size: 15px;
            font-weight: 600;
            text-decoration: none;
            border: 1px solid transparent;
        }

        .button-primary { background: var(--accent); color: #FFFFFF; }
        .button-primary:hover { background: var(--accent-dark); }

        .button-secondary {
            background: transparent;
            color: var(--ink);
            border-color: var(--border);
        }
        .button-secondary:hover { border-color: var(--muted); }

        .detail {
            margin-top: 24px;
            padding-top: 20px;
            border-top: 1px solid var(--border);
            font-size: 14px;
            color: var(--muted);
        }

        .detail code {
            font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
            font-size: 13px;
            word-break: break-all;
            color: var(--body);
        }

        .footer {
            margin-top: 24px;
            text-align: center;
            font-size: 13px;
            color: var(--muted);
        }

        @media (max-width: 480px) {
            .card { padding: 28px 22px; }
            h1 { font-size: 25px; }
            .actions { flex-direction: column; }
            .button { text-align: center; }
        }
    </style>
</head>
<body>
    <main class="page">
        <div class="brand">
            <div class="brand-mark">🎓</div>
            <div>
                <div class="brand-name">School365ai</div>
                <div class="brand-tagline">Smarter Schools. Brighter Futures.</div>
            </div>
        </div>

        <div class="card">
            @yield('content')
        </div>

        <p class="footer">© {{ date('Y') }} School365ai</p>
    </main>
</body>
</html>
