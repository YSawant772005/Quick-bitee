"""Deterministic primary keys shared by every seeding path.

``scripts/seed_catalogue.py`` and ``app.seed`` must agree on the id a row gets,
otherwise a re-seed inserts a second row for the same logical entity (the
unique *slug* indexes then reject it, or worse, duplicate dishes appear).
One namespace + one join convention, imported everywhere.
"""

from __future__ import annotations

import uuid

#: Fixed namespace — changing this would orphan every previously seeded row.
NAMESPACE = uuid.UUID("6fa459ea-ee8a-3ca4-894e-db77e160355e")


def stable_id(*parts: str) -> str:
    """Deterministic UUIDv5 from the parts identifying the row."""
    return str(uuid.uuid5(NAMESPACE, "|".join(parts)))
