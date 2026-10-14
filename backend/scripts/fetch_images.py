"""Download and verify real food photographs for the seeded catalog.

Each catalog image slug has an ordered list of candidate Unsplash URLs. The first
candidate that returns HTTP 200 with an image content type and a sane size is saved
to app/static/catalog/<slug>.jpg and recorded in docs/IMAGES.md with attribution.

Run from backend/:
    python -m scripts.fetch_images
"""
import asyncio
from pathlib import Path

import httpx

STATIC_DIR = Path(__file__).resolve().parent.parent / "app" / "static" / "catalog"
ATTRIBUTION_PATH = Path(__file__).resolve().parent.parent.parent / "docs" / "IMAGES.md"

Q = "?auto=format&fit=crop&w=800&q=60"
U = "https://images.unsplash.com/photo-"

CANDIDATES: dict[str, list[str]] = {
    # restaurant covers
    "rest-biryani": [f"{U}1589302168068-964664d93dc0{Q}", f"{U}1606491956689-2ea866880c84{Q}"],
    "rest-pizza": [f"{U}1513104890138-7c749659a591{Q}", f"{U}1574071318508-1cdbab80d002{Q}"],
    "rest-burger": [f"{U}1568901346375-23c9450c58cd{Q}", f"{U}1550547660-d9450f859349{Q}"],
    "rest-dosa": [f"{U}1630383249896-424e482df921{Q}", f"{U}1589301760014-d929f3979dbc{Q}"],
    "rest-punjabi": [f"{U}1585937421612-70a008356fbe{Q}", f"{U}1567337710282-00832b415979{Q}"],
    "rest-asian": [f"{U}1585032226651-759b368d7246{Q}", f"{U}1552611052-33e04de081de{Q}"],
    "rest-dessert": [f"{U}1551024506-0bccd828d307{Q}", f"{U}1565958011703-44f9829ba187{Q}"],
    "rest-chai": [f"{U}1571934811356-5cc061b6821f{Q}", f"{U}1544787219-7f47ccb76574{Q}"],
    # biryani house
    "dish-chicken-biryani": [f"{U}1606491956689-2ea866880c84{Q}", f"{U}1589302168068-964664d93dc0{Q}"],
    "dish-veg-biryani": [f"{U}1512058564366-18510be2db19{Q}", f"{U}1536304993881-ff6e9eefa2a6{Q}"],
    "dish-chicken65-biryani": [f"{U}1563379091339-03b21ab4a4f8{Q}", f"{U}1606491956689-2ea866880c84{Q}"],
    "dish-mirchi-ka-salan": [f"{U}1567337710282-00832b415979{Q}", f"{U}1585937421612-70a008356fbe{Q}"],
    "dish-double-ka-meetha": [f"{U}1488477181946-6428a0291777{Q}", f"{U}1551024506-0bccd828d307{Q}"],
    # pizzeria
    "dish-margherita": [f"{U}1574071318508-1cdbab80d002{Q}", f"{U}1593560708920-61dd98c46a4e{Q}"],
    "dish-pepperoni": [f"{U}1593560708920-61dd98c46a4e{Q}", f"{U}1628840042765-356cda07504e{Q}"],
    "dish-farmhouse": [f"{U}1511689660979-10d2b1aada49{Q}", f"{U}1565299624946-b28f40a0ae38{Q}"],
    "dish-breadsticks": [f"{U}1573140247632-f8fd74997d5c{Q}", f"{U}1549931319-a545dcf3bc73{Q}"],
    "dish-lava-cake": [f"{U}1624353365286-3f8d62daad51{Q}", f"{U}1606313564200-e75d5e30476c{Q}"],
    # burger barn
    "dish-cheeseburger": [f"{U}1553979459-d2229ba7433b{Q}", f"{U}1568901346375-23c9450c58cd{Q}"],
    "dish-crispy-chicken-burger": [f"{U}1606755962773-d324e0a13086{Q}", f"{U}1550547660-d9450f859349{Q}"],
    "dish-paneer-burger": [f"{U}1551782450-a2132b4ba21d{Q}", f"{U}1520072959214-cd1961f6c9de{Q}"],
    "dish-peri-fries": [f"{U}1541592106381-b31e9677c0e5{Q}", f"{U}1585109149139-5fbd6ef5ece2{Q}"],
    "dish-thickshake": [f"{U}1579954115545-a95591f28bfc{Q}", f"{U}1437418747212-8d9709afab22{Q}"],
    # dosa district
    "dish-masala-dosa": [f"{U}1589301760014-d929f3979dbc{Q}", f"{U}1630383249896-424e482df921{Q}"],
    "dish-paneer-dosa": [f"{U}1666190092159-3171cf0fbb12{Q}", f"{U}1630383249896-424e482df921{Q}"],
    "dish-idli": [f"{U}1589301760014-d929f3979dbc{Q}", f"{U}1631452180519-c014fe946bc7{Q}"],
    "dish-bonda": [f"{U}1601050690597-df0568f70950{Q}", f"{U}1606491956689-2ea866880c84{Q}"],
    "dish-filter-coffee": [f"{U}1544787219-7f47ccb76574{Q}", f"{U}1509042239860-f550ce710b93{Q}"],
    # punjabi tadka
    "dish-butter-chicken": [f"{U}1603894584373-5ac82b2ae398{Q}", f"{U}1585937421612-70a008356fbe{Q}"],
    "dish-paneer-tikka": [f"{U}1631452180519-c014fe946bc7{Q}", f"{U}1599487488170-d11ec9c172f0{Q}"],
    "dish-dal-makhani": [f"{U}1546833999-b9f581a1996d{Q}", f"{U}1585937421612-70a008356fbe{Q}"],
    "dish-kulcha": [f"{U}1601050690597-df0568f70950{Q}", f"{U}1626074353765-517a681e40be{Q}"],
    "dish-gulab-jamun": [f"{U}1627308595229-7830a5c91f9f{Q}", f"{U}1551024506-0bccd828d307{Q}"],
    # wok this way
    "dish-hakka-noodles": [f"{U}1585032226651-759b368d7246{Q}", f"{U}1563245372-f21724e3856d{Q}"],
    "dish-manchurian": [f"{U}1625398407796-82650a8c135f{Q}", f"{U}1512058564366-18510be2db19{Q}"],
    "dish-thai-fried-rice": [f"{U}1536304993881-ff6e9eefa2a6{Q}", f"{U}1603133872878-684f208fb84b{Q}"],
    "dish-ramen": [f"{U}1557872943-16a5ac26437e{Q}", f"{U}1569718212165-3a8278d5f624{Q}"],
    "dish-spring-rolls": [f"{U}1526318896980-cf78c088247c{Q}", f"{U}1540189549336-e6e99c3679fe{Q}"],
    # sugar rush
    "dish-cheesecake": [f"{U}1533134242443-d4fd215305ad{Q}", f"{U}1481391319762-47dff72954d9{Q}"],
    "dish-brownie": [f"{U}1606313564200-e75d5e30476c{Q}", f"{U}1624353365286-3f8d62daad51{Q}"],
    "dish-tiramisu": [f"{U}1571115177098-24ec42ed204d{Q}", f"{U}1712262582533-dcd8e9b171f9{Q}"],
    "dish-mango-sundae": [f"{U}1563805042-7684c019e1cb{Q}", f"{U}1560008581-09826d1de69e{Q}"],
    "dish-red-velvet": [f"{U}1617093727343-374698b1b08d{Q}", f"{U}1586788680434-30d324b2d46f{Q}"],
    # chai sutta
    "dish-kadak-chai": [f"{U}1571934811356-5cc061b6821f{Q}", f"{U}1544787219-7f47ccb76574{Q}"],
    "dish-cold-coffee": [f"{U}1461023058943-07fcbe16d735{Q}", f"{U}1495474472287-4d71bcdd2085{Q}"],
    "dish-mango-lassi": [f"{U}1626200419199-391ae4be7a41{Q}", f"{U}1553530666-ba11a7da3888{Q}"],
    "dish-lime-soda": [f"{U}1438522014717-d7ce32b9bab9{Q}", f"{U}1572490122747-3968b75cc699{Q}"],
    "dish-shikanji": [f"{U}1572490122747-3968b75cc699{Q}", f"{U}1556679343-c7306c1976bc{Q}"],
}

MIN_BYTES = 15 * 1024


async def try_download(client: httpx.AsyncClient, url: str) -> bytes | None:
    try:
        resp = await client.get(url, timeout=30.0, follow_redirects=True)
    except httpx.HTTPError:
        return None
    if resp.status_code != 200:
        return None
    if "image" not in resp.headers.get("content-type", ""):
        return None
    if len(resp.content) < MIN_BYTES:
        return None
    return resp.content


async def main() -> None:
    STATIC_DIR.mkdir(parents=True, exist_ok=True)
    results: dict[str, str] = {}
    failures: list[str] = []
    async with httpx.AsyncClient() as client:
        for slug, urls in CANDIDATES.items():
            data = None
            used = ""
            for url in urls:
                data = await try_download(client, url)
                if data is not None:
                    used = url
                    break
            if data is None:
                failures.append(slug)
                print(f"FAIL {slug}")
                continue
            (STATIC_DIR / f"{slug}.jpg").write_bytes(data)
            results[slug] = used
            print(f"OK   {slug} ({len(data) // 1024} KB)")

    lines = [
        "# QuickBite catalog image sources",
        "",
        "All photographs are from [Unsplash](https://unsplash.com) and are free to use",
        "under the [Unsplash License](https://unsplash.com/license). Downloaded and",
        "verified by `backend/scripts/fetch_images.py`.",
        "",
        "| Catalog file | Source |",
        "|---|---|",
    ]
    for slug, url in sorted(results.items()):
        lines.append(f"| {slug}.jpg | {url} |")
    ATTRIBUTION_PATH.parent.mkdir(exist_ok=True)
    ATTRIBUTION_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\nsaved {len(results)}/{len(CANDIDATES)} images; failures: {failures or 'none'}")


if __name__ == "__main__":
    asyncio.run(main())
