"""Response headers every API answer carries (Phase 21, docs/security.md).

Django's SecurityMiddleware covers HSTS, nosniff and the referrer policy, and
XFrameOptionsMiddleware framing. What it has no setting for is a Content
Security Policy, which is this.
"""

from __future__ import annotations

# The API returns JSON, CSV and PDF - never a page with scripts, styles or
# images of its own - so the policy allows nothing and forbids framing.
POLICY = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"


class ContentSecurityPolicyMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        response.setdefault("Content-Security-Policy", POLICY)
        return response
