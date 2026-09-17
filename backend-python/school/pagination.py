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

import re
from collections import OrderedDict

from django.core.paginator import Page, Paginator
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


# What PHP's FILTER_VALIDATE_INT accepts once surrounding whitespace is gone:
# an optional sign and plain decimal digits, with no leading zeros. "2.5",
# "1e1" and "02" are not integers to it.
PHP_INTEGER = re.compile(r"^[+-]?(0|[1-9][0-9]*)$")


def resolve_page(requested) -> int:
    """Reads `page` off a query string the way Laravel's paginator does.

    Anything that is not a whole number of at least 1 is page 1, never an
    error - junk, zero and negatives included. DRF's own paginator answers 404
    to all of those, and to a page past the end, which is how every Python
    list disagreed with Laravel from M8 until this was found: no test and no
    diff had ever asked for a page that did not exist.
    """
    if requested is None:
        return 1

    text = str(requested).strip(" \t\n\r\x0b\x0c")

    if not PHP_INTEGER.match(text):
        return 1

    number = int(text)

    return number if number >= 1 else 1


class LaravelPagination(PageNumberPagination):
    page_size = DEFAULT_PER_PAGE
    page_size_query_param = "per_page"
    max_page_size = MAX_PER_PAGE
    page_query_param = "page"

    def get_page_size(self, request):
        if self.page_size_query_param not in request.query_params:
            return DEFAULT_PER_PAGE

        return resolve_per_page(request.query_params[self.page_size_query_param])

    def paginate_queryset(self, queryset, request, view=None):
        """One page of rows, and never a 404.

        A page past the end is an empty page that still reports the number
        asked for, exactly as Laravel's LengthAwarePaginator does - so a client
        that deletes the last row on the last page, and asks for that page
        again, gets an empty list rather than an error.
        """
        self.request = request

        paginator = Paginator(queryset, self.get_page_size(request))
        number = resolve_page(request.query_params.get(self.page_query_param))

        if number <= paginator.num_pages:
            self.page = paginator.page(number)
        else:
            self.page = Page([], number, paginator)

        return list(self.page)

    def get_paginated_response(self, data) -> Response:
        page = self.page
        paginator = page.paginator

        # Laravel counts from 1 and reports `from`/`to` as null on an empty
        # page rather than 0. A client that renders "showing 0 to 0 of 0" is
        # reading a different backend.
        # Django's own start/end index would count positions on a page past
        # the end; Laravel says null for any page with nothing on it.
        first_on_page = page.start_index() if len(page.object_list) else None
        last_on_page = page.end_index() if len(page.object_list) else None

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
                            "links": self.link_collection(page.number, paginator.num_pages),
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

    # -- meta.links ---------------------------------------------------------
    #
    # The page-link descriptors Laravel's `linkCollection()` produces: a
    # "Previous", one entry per page shown, and a "Next", with `...` standing
    # in for the pages a long list elides.
    #
    # Nothing in the Flutter client reads this. It is here because this file
    # claims to reproduce Laravel's envelope and a claim like that is either
    # true or it is a trap for whoever relies on it next - and because the
    # first cross-backend diff of /schools found it missing, which is exactly
    # the sort of quiet gap that comparison exists to catch.
    #
    # Ported from Illuminate\Pagination\UrlWindow, which decides how many
    # pages to show, and LengthAwarePaginator::linkCollection(), which wraps
    # them. ON_EACH_SIDE is Laravel's default.

    ON_EACH_SIDE = 3

    def link_collection(self, current: int, last: int) -> list[dict]:
        links = [
            {
                "url": self.page_url(current - 1) if current > 1 else None,
                "label": "&laquo; Previous",
                "page": current - 1 if current > 1 else None,
                "active": False,
            }
        ]

        for page in self.window(current, last):
            if page is None:
                links.append({"url": None, "label": "...", "active": False})
            else:
                links.append(
                    {
                        "url": self.page_url(page),
                        "label": str(page),
                        "page": page,
                        "active": page == current,
                    }
                )

        links.append(
            {
                "url": self.page_url(current + 1) if current < last else None,
                "label": "Next &raquo;",
                "page": current + 1 if current < last else None,
                "active": False,
            }
        )

        return links

    @classmethod
    def window(cls, current: int, last: int) -> list[int | None]:
        """Which page numbers to show, with None for an elision.

        Laravel's UrlWindow, arm for arm. Short lists show every page; long
        ones show a start, a slider around the current page, and an end.
        """
        on_each_side = cls.ON_EACH_SIDE

        # Short enough to show every page. The threshold is Laravel's, and
        # note it is `<`, not `<=`: at exactly 14 pages the slider starts.
        if last < on_each_side * 2 + 8:
            return list(range(1, last + 1))

        window = on_each_side + 4

        if current <= window:
            return cls.join(list(range(1, window + on_each_side + 1)), None, [last - 1, last])

        if current > last - window:
            start = last - (window + on_each_side - 1)

            return cls.join([1, 2], None, list(range(start, last + 1)))

        return cls.join(
            [1, 2],
            None,
            list(range(current - on_each_side, current + on_each_side + 1)),
            None,
            [last - 1, last],
        )

    @staticmethod
    def join(*parts) -> list:
        """Flattens the segments of a window, keeping the None separators."""
        flattened = []

        for part in parts:
            if part is None:
                flattened.append(None)
            else:
                flattened.extend(part)

        return flattened
