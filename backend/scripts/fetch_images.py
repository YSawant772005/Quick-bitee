"""Fetch local, licensed photographs for every food type the catalogue uses.

Design
------
* Deterministic: the required set comes from :func:`app.catalog.build.build_catalogue`,
  so two runs ask for exactly the same photographs.
* Local only: every image is downloaded into ``app/static/catalog`` and served
  from ``/static``. Nothing in the API or the app points at Wikimedia directly.
* Licensed: only Wikimedia Commons results (CC0/PD/CC BY/CC BY-SA) are used and
  the licence, author and source page are recorded in ``manifest.json``.
* Verified: a candidate is only accepted after Pillow decodes it, and it must be
  at least ``MIN_WIDTH`` px wide. A search hit that cannot be decoded is skipped
  rather than saved.
* Idempotent: an existing valid file is reused, so re-running the script does
  not re-download anything.

Usage::

    .venv\\Scripts\\python.exe scripts\\fetch_images.py            # fetch gaps
    .venv\\Scripts\\python.exe scripts\\fetch_images.py --dry-run  # only report
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path

import httpx
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.catalog.build import build_catalogue  # noqa: E402
from app.catalog import taxonomy  # noqa: E402

API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "QuickBiteeCatalog/1.0 (catalogue seeding; admin@quickbite.dev)"
OUT_DIR = Path(__file__).resolve().parents[1] / "app" / "static" / "catalog"
MANIFEST_PATH = OUT_DIR / "manifest.json"

MIN_WIDTH = 500
MIN_HEIGHT = 350
MIN_BYTES = 12_000
MAX_WIDTH = 1400
JPEG_QUALITY = 86
SEARCH_LIMIT = 8
USER_AGENT_ = USER_AGENT

#: Words that carry no signal when matching a Commons file title against the
#: food-type label.
_STOP = {
    "and", "the", "with", "of", "a", "an", "in", "on", "at", "style", "styles",
    "fresh", "puree", "made", "served", "cut", "hot", "cold",
}


# ---------------------------------------------------------------------------
# required set
# ---------------------------------------------------------------------------

def required_food_types() -> list[str]:
    """Every food type that needs a photograph, sorted for stable output."""
    catalogue = build_catalogue()
    needed: set[str] = set(catalogue.all_food_types())
    # A dish may resolve along a fallback chain; those steps need art too.
    for food_type in list(needed):
        needed.update(taxonomy.resolve_food_types(food_type))
    return sorted(needed)


def tokens(text: str) -> set[str]:
    out = set()
    for raw in re.split(r"[^a-z0-9]+", text.lower()):
        token = raw
        if len(token) > 3 and token.endswith("s") and not token.endswith("ss"):
            token = token[:-1]
        if len(token) >= 3 and token not in _STOP:
            out.add(token)
    return out


# ---------------------------------------------------------------------------
# existing assets
# ---------------------------------------------------------------------------

def seed_mapping(food_types: list[str]) -> dict[str, str]:
    """Match the pre-existing photographs to food types by name."""
    mapping: dict[str, str] = {}
    if not OUT_DIR.is_dir():
        return mapping

    index: dict[str, set[str]] = {
        food_type: tokens(f"{food_type} {taxonomy.FOOD_TYPES.get(food_type, '')}")
        for food_type in food_types
    }

    for path in sorted(OUT_DIR.glob("*.jpg")):
        if path.name == MANIFEST_PATH.name:
            continue
        stem = path.stem
        if stem.startswith("dish-"):
            stem = stem[5:]
        elif stem.startswith("rest-"):
            stem = stem[5:]
        file_tokens = tokens(stem)
        if not file_tokens:
            continue
        best, best_score = None, 0.0
        for food_type, ft_tokens in index.items():
            if not ft_tokens:
                continue
            overlap = len(file_tokens & ft_tokens)
            score = overlap / len(file_tokens)
            if score > best_score:
                best, best_score = food_type, score
        if best is not None and best_score >= 0.66 and best not in mapping:
            mapping[best] = path.name
    return mapping


# ---------------------------------------------------------------------------
# Wikimedia Commons
# ---------------------------------------------------------------------------

@dataclass
class Asset:
    food_type: str
    file: str
    origin: str  # "seed" | "commons"
    query: str
    title: str = ""
    page_url: str = ""
    license: str = ""
    author: str = ""
    width: int = 0
    height: int = 0
    bytes: int = 0


def search(client: httpx.Client, query: str) -> list[dict]:
    params = {
        "action": "query",
        "format": "json",
        "formatversion": "2",
        "generator": "search",
        "gsrsearch": f"{query} filetype:bitmap",
        "gsrnamespace": "6",
        "gsrlimit": str(SEARCH_LIMIT),
        "prop": "imageinfo",
        "iiprop": "url|extmetadata|size",
        "iiurlwidth": str(MAX_WIDTH),
    }
    try:
        response = client.get(API, params=params, headers={"User-Agent": USER_AGENT})
        response.raise_for_status()
    except httpx.HTTPError:
        return []
    payload = response.json()
    return payload.get("query", {}).get("pages", []) or []


def decode_ok(data: bytes) -> tuple[int, int] | None:
    if len(data) < MIN_BYTES:
        return None
    try:
        with Image.open(io.BytesIO(data)) as image:
            image.load()
            width, height = image.size
    except Exception:
        return None
    if width < MIN_WIDTH or height < MIN_HEIGHT:
        return None
    return width, height


def normalise(data: bytes) -> bytes | None:
    """Decode, flatten onto white and re-encode as JPEG at a sane size."""
    try:
        with Image.open(io.BytesIO(data)) as image:
            image.load()
            if image.mode in ("RGBA", "LA", "P"):
                background = Image.new("RGB", image.size, (255, 255, 255))
                rgba = image.convert("RGBA")
                background.paste(rgba, mask=rgba.split()[-1])
                image = background
            else:
                image = image.convert("RGB")
            if image.width > MAX_WIDTH:
                ratio = MAX_WIDTH / image.width
                image = image.resize(
                    (MAX_WIDTH, max(1, int(image.height * ratio))), Image.LANCZOS
                )
            buffer = io.BytesIO()
            image.save(buffer, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    except Exception:
        return None
    return buffer.getvalue()


def fetch_one(
    client: httpx.Client, food_type: str, query: str
) -> Asset | None:
    """Try to fetch and verify a photograph for ``food_type``."""
    for step in taxonomy.resolve_food_types(food_type):
        label = taxonomy.FOOD_TYPES.get(step)
        if not label:
            continue
        wanted = tokens(f"{food_type} {label}")
        pages = search(client, query if step == food_type else label)
        ordered = []
        for page in pages:
            title = page.get("title", "")
            if not title.lower().endswith((".jpg", ".jpeg", ".png", ".webp")):
                continue
            score = len(wanted & tokens(title))
            ordered.append((score, page))
        ordered.sort(key=lambda pair: pair[0], reverse=True)

        for score, page in ordered:
            if score <= 0:
                continue
            info = (page.get("imageinfo") or [{}])[0]
            url = info.get("thumburl") or info.get("url")
            if not url:
                continue
            try:
                response = client.get(url, headers={"User-Agent": USER_AGENT})
                response.raise_for_status()
                data = response.content
            except httpx.HTTPError:
                continue
            if decode_ok(data) is None:
                continue
            normalised = normalise(data)
            if not normalised:
                continue
            meta = info.get("extmetadata", {}) or {}
            asset = Asset(
                food_type=food_type,
                file=f"{food_type}.jpg",
                origin="commons",
                query=query,
                title=page.get("title", "").replace("File:", ""),
                page_url=info.get("descriptionurl", ""),
                license=str(meta.get("LicenseShortName", {}).get("value", "")),
                author=re.sub(
                    r"<[^>]+>",
                    "",
                    str(meta.get("Artist", {}).get("value", "")),
                ).strip()[:120],
                width=info.get("width", 0),
                height=info.get("height", 0),
                bytes=len(normalised),
            )
            (OUT_DIR / asset.file).write_bytes(normalised)
            return asset
    return None


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def verify_existing(path: Path) -> tuple[int, int] | None:
    try:
        data = path.read_bytes()
    except OSError:
        return None
    return decode_ok(data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="report only")
    parser.add_argument("--limit", type=int, default=0, help="stop after N fetches")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    food_types = required_food_types()
    seeds = seed_mapping(food_types)

    manifest: dict[str, Asset] = {}
    gaps: list[str] = []
    reused = 0

    for food_type in food_types:
        filename = seeds.get(food_type, f"{food_type}.jpg")
        path = OUT_DIR / filename
        size = verify_existing(path) if path.exists() else None
        if size is None:
            gaps.append(food_type)
            if filename != f"{food_type}.jpg":
                # The seeded file is unusable; fetch a dedicated one.
                filename = f"{food_type}.jpg"
            continue
        manifest[food_type] = Asset(
            food_type=food_type,
            file=filename,
            origin="seed" if food_type in seeds else "local",
            query=taxonomy.FOOD_TYPES.get(food_type, ""),
            width=size[0],
            height=size[1],
            bytes=path.stat().st_size,
        )
        reused += 1

    print(f"food types required: {len(food_types)}")
    print(f"already on disk:     {reused}")
    print(f"to fetch:            {len(gaps)}")

    if args.dry_run:
        print("\nGAPS:")
        for food_type in gaps:
            print(f"  {food_type:32} {taxonomy.FOOD_TYPES.get(food_type, '?')}")
        return 1 if gaps else 0

    fetched = 0
    failed: list[str] = []
    with httpx.Client(timeout=40.0, follow_redirects=True) as client:
        for food_type in gaps:
            label = taxonomy.FOOD_TYPES.get(food_type)
            if not label:
                failed.append(food_type)
                continue
            asset = fetch_one(client, food_type, label)
            if asset is None:
                failed.append(food_type)
                print(f"  MISS {food_type:32} {label}")
            else:
                manifest[food_type] = asset
                fetched += 1
                print(f"  OK   {food_type:32} {label}  ({asset.width}x{asset.height})")
            if args.limit and fetched >= args.limit:
                break
            time.sleep(0.05)

    payload = {
        "generated": time.strftime("%Y-%m-%d", time.gmtime()),
        "count": len(manifest),
        "assets": {key: asdict(value) for key, value in sorted(manifest.items())},
    }
    MANIFEST_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print()
    print(f"reused:  {reused}")
    print(f"fetched: {fetched}")
    print(f"failed:  {len(failed)}")
    if failed:
        for food_type in failed:
            print(f"   {food_type:32} {taxonomy.FOOD_TYPES.get(food_type, '?')}")
    print(f"manifest: {MANIFEST_PATH}")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
