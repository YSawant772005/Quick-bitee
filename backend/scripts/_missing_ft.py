from app.catalog import taxonomy
from app.catalog.build import build_catalogue

cat = build_catalogue()
needed = set(cat.all_food_types())
for ft in list(needed):
    needed.update(taxonomy.resolve_food_types(ft))

missing = sorted(ft for ft in needed if ft not in taxonomy.FOOD_TYPES)
print("required but NOT in FOOD_TYPES:", len(missing))
for ft in missing:
    print("  ", ft)
