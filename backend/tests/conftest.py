"""Process-wide test isolation, imported by pytest before any test module.

Test files redirect DATABASE_URL to their own temp database at import time,
but app.core.config caches Settings on the FIRST app import: when a test file
that never sets DATABASE_URL (e.g. test_qwen_fallback) is imported first in a
combined run, the engine binds to the real .env database and the
schema-resetting fixtures wipe real dev data. Setting the env here, before any
test module or app code loads, guarantees every run uses a throwaway database.
"""

import os
import tempfile
from pathlib import Path

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault(
    "DATABASE_URL",
    f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'erlang_conftest_pytest.db').as_posix()}",
)
