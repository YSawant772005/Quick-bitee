from collections import defaultdict

from app.catalog import taxonomy
from app.catalog.recipes import RECIPES

by = defaultdict(list)
for k, r in RECIPES.items():
    for t in r.tags:
        by[t].append(k)

for slug, _name, _desc, _thumb, _order in sorted(
    taxonomy.GLOBAL_CATEGORIES, key=lambda x: x[4]
):
    print(f"{slug:20} {len(by[slug]):>2}  {', '.join(by[slug])}")

print()
print(
    "global categories with NO recipe:",
    [s for s, *_ in taxonomy.GLOBAL_CATEGORIES if not by[s]],
)
