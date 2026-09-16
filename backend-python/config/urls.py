"""The routes this backend serves.

Empty on purpose at M7. The skeleton's job is models, settings and a test
harness; endpoints arrive at M8 with auth and tenancy, and then module by
module from M9 - each one landing only when its contract tests pass
(../contract/README.md).

Everything will hang under /api/v1/ because that is what the Flutter apps
already call. The prefix is not a style choice; it is part of the contract.
"""

from django.urls import path

urlpatterns: list[path] = []
