"""The list envelope: `{data, links, meta}`.

Written rather than configured, because DRF's own paginator answers
`{count, next, previous, results}` and the Flutter client cannot read it - it
looks for `data` and four keys inside `meta` (see
frontend/lib/core/network/paginated_response.dart). Changing the client to
match DRF would be a contract change, and rule 1 of the migration is that the
contract does not change.

So this reproduces what Laravel's ResourceCollection emits for a
LengthAwarePaginator, including the parts nothing currently reads. Emitting
less than Laravel does would mean guessing which of those parts nobody will
ever read, and an omission that turns out to be wrong shows up as a null
dereference in a client nobody is allowed to change.
"""

from __future__ import annotations

from collections import OrderedDict

from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response

# Laravel's Support\Pagination: 20 a page by default, never more than 100, so
# a client can ask for a bigger page without being able to ask for the lot.
DEFAULT_PER_PAGE = 20
MAX_PER_PAGE = 100


def resolve_per_page(requested) -> int:
    """Reads `per_page` off a query string and clamps it.

    Anything that is not a positive number falls back to the default rather
    than raising: Laravel's `(int) $filters['per_page']` turns "abc" into 0,
    which its own `> 0` check then rejects, and a list endpoint that answers
    422 because of a junk page size would be new behaviour.
    """
    try:
        value = int(requested)
    except (TypeError, ValueError):
        return DEFAULT_PER_PAGE

    return min(MAX_PER_PAGE, value) if value > 0 else DEFAULT_PER_PAGE


class LaravelPagination(PageNumberPagination):
    page_size = DEFAULT_PER_PAGE
    page_size_query_param = "per_page"
    max_page_size = MAX_PER_PAGE
    page_query_param = "page"

    def get_page_size(self, request):
        if self.page_size_query_param not in request.query_params:
            return DEFAULT_PER_PAGE

        return resolve_per_page(request.query_params[self.page_size_query_param])

    def get_paginated_response(self, data) -> Response:
        page = self.page
        paginator = page.paginator

        # Laravel counts from 1 and reports `from`/`to` as null on an empty
        # page rather than 0. A client that renders "showing 0 to 0 of 0" is
        # reading a different backend.
        first_on_page = page.start_index() or None
        last_on_page = page.end_index() or None

        return Response(
            OrderedDict(
                [
                    ("data", data),
                    (
                        "links",
                        {
                            "first": self.page_url(1),
                            "last": self.page_url(paginator.num_pages),
                            "prev": self.page_url(page.number - 1) if page.has_previous() else None,
                            "next": self.page_url(page.number + 1) if page.has_next() else None,
                        },
                    ),
                    (
                        "meta",
                        {
                            "current_page": page.number,
                            "from": first_on_page,
                            # Laravel reports at least one page even when there
                            # is nothing to show; Django's paginator agrees, but
                            # only because it is configured to allow an empty
                            # first page.
                            "last_page": paginator.num_pages,
                            "path": self.path(),
                            "per_page": self.get_page_size(self.request),
                            "to": last_on_page,
                            "total": paginator.count,
                        },
                    ),
                ]
            )
        )

    def path(self) -> str:
        """The request URL without its query string, which is what Laravel
        puts in `meta.path`."""
        return self.request.build_absolute_uri(self.request.path)

    def page_url(self, number: int) -> str:
        return f"{self.path()}?page={number}"
