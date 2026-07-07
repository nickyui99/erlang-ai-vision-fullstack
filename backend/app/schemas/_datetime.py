from datetime import UTC, datetime
from typing import Annotated

from pydantic import AfterValidator, PlainSerializer


def _ensure_utc(value: datetime) -> datetime:
    # asyncpg rejects naive datetimes for timestamptz columns; edge firmware
    # sends UTC by convention, so naive input is interpreted as UTC. Aware
    # values are converted: SQLite storage drops the offset without converting,
    # so a non-UTC wall time would otherwise be persisted as-is.
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _serialize_utc(value: datetime) -> str:
    # Always emit an explicit UTC marker ("...Z"). SQLite returns naive
    # datetimes (offset dropped on storage), so without this the API would send
    # tz-less strings that clients like Dart's DateTime.parse treat as LOCAL
    # time — shifting every displayed timestamp by the viewer's UTC offset.
    aware = value if value.tzinfo is not None else value.replace(tzinfo=UTC)
    return aware.astimezone(UTC).isoformat().replace("+00:00", "Z")


# Use for every datetime field that is serialized back to clients. The validator
# normalizes input to UTC; the serializer guarantees a "Z"-suffixed UTC string.
UTCDatetime = Annotated[
    datetime,
    AfterValidator(_ensure_utc),
    PlainSerializer(_serialize_utc, return_type=str, when_used="json"),
]
