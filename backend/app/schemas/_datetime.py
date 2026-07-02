from datetime import UTC, datetime
from typing import Annotated

from pydantic import AfterValidator


def _ensure_utc(value: datetime) -> datetime:
    # asyncpg rejects naive datetimes for timestamptz columns; edge firmware
    # sends UTC by convention, so naive input is interpreted as UTC. Aware
    # values are converted: SQLite storage drops the offset without converting,
    # so a non-UTC wall time would otherwise be persisted as-is.
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


UTCDatetime = Annotated[datetime, AfterValidator(_ensure_utc)]
