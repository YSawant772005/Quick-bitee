"""Validate every image referenced by the catalogue exists, decodes and is food-appropriate."""
from __future__ import annotations

import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PIL import Image

from app.catalog.build import build_catalogue
from app.catalog import taxonomy

OUT_DIR = Path(__file__).resolve().parents[1] / "app" / "static" / "catalog"
MANIFEST_PATH = OUT_DIR / "manifest.json"

MIN_WIDTH = 500
MIN_HEIGHT = 350
MIN_BYTES = 12_000


def verify(path: Path) -> tuple[bool, str]:
    try:
        data = path.read_bytes()
    except OSError:
        return False, "missing"
    if len(data) < MIN_BYTES:
        return False, f"too small ({len(data)} bytes)"
    try:
        with Image.open(io.BytesIO(data)) as img:
            img.load()
            w, h = img.size
    except Exception as e:
        return False, f"decode error: {e}"
    if w < MIN_WIDTH or h < MIN_HEIGHT:
        return False, f"too small ({w}x{h})"
    return True, "ok"


def main() -> int:
    import io

    catalogue = build_catalogue()
    needed = set(catalogue.all_food_types())
    for ft in list(needed):
        needed.update(taxonomy.resolve_food_types(ft))

    missing = 0
    bad = 0
    for food_type in sorted(needed):
        # manifest may remap to a different filename (e.g., seed images)
        path = OUT_DIR / f"{food_type}.jpg"
        if not path.exists():
            # check if manifest has an alias
            if MANIFEST_PATH.exists():
                import json
                manifest = json.loads(MANIFEST_PATH.read_text())
                entry = manifest["assets"].get(food_type)
                if entry and entry["origin"] in ("seed", "local"):
                    path = OUT_DIR / entry["file"]
        if not path.exists():
            print(f"MISSING {food_type}")
            missing += 1
            continue
        ok, msg = verify(path)
        if not ok:
            print(f"INVALID {food_type} ({path.name}): {msg}")
            bad += 1

    print(f"\nchecked: {len(needed)}  missing: {missing}  invalid: {bad}")
    return 1 if (missing or bad) else 0


if __name__ == "__main__":
    raise SystemExit(main())