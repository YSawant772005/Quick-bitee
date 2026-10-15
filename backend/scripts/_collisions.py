"""Find dish names that appear in more than one recipe pool (collision risk
when two recipes end up on the same restaurant menu)."""
from collections import defaultdict

from app.catalog.recipes import RECIPES

where = defaultdict(set)
for key, r in RECIPES.items():
    for d in r.candidates():
        where[d.name].add(key)

multi = {n: sorted(k) for n, k in where.items() if len(k) > 1}
print("names shared by 2+ recipes:", len(multi))
for n, k in sorted(multi.items())[:60]:
    print(f"  {n:34} {', '.join(k)}")
