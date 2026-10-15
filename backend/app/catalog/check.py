"""Sanity-check the catalogue generator before touching the database."""

from __future__ import annotations

import sys
from collections import Counter

from app.catalog import taxonomy
from app.catalog.dishes import bind_food_types
from app.catalog.recipes import RECIPES

bind_food_types(set(taxonomy.FOOD_TYPES))

problems: list[str] = []
print(f"{'recipe':26} {'title':24} {'pool':>5}  veg  nonveg  tags")
print("-" * 96)

for key, recipe in RECIPES.items():
    pool = recipe.candidates()
    veg = sum(1 for d in pool if d.veg)
    nonveg = len(pool) - veg
    print(f"{key:26} {recipe.title:24} {len(pool):>5}  {veg:>3}  {nonveg:>6}  {','.join(recipe.tags)}")
    if len(pool) < 40:
        problems.append(f"recipe {key!r} only has {len(pool)} candidates (<40)")
    names = [d.name for d in pool]
    dupes = [n for n, c in Counter(names).items() if c > 1]
    if dupes:
        problems.append(f"recipe {key!r} has duplicate names: {dupes[:5]}")
    descs = [d.description for d in pool]
    dupes = [d[:60] for d, c in Counter(descs).items() if c > 1]
    if dupes:
        problems.append(f"recipe {key!r} has duplicate descriptions: {dupes[:3]}")
    for dish in pool:
        if dish.food_type not in taxonomy.FOOD_TYPES:
            problems.append(
                f"recipe {key!r} dish {dish.name!r} uses unknown food type {dish.food_type!r}"
            )
        for tag in dish.tags:
            if tag not in taxonomy.GLOBAL_CATEGORY_SLUGS:
                problems.append(
                    f"recipe {key!r} dish {dish.name!r} uses unknown tag {tag!r}"
                )
        if not dish.description or len(dish.description) < 15:
            problems.append(
                f"recipe {key!r} dish {dish.name!r} has a weak description"
            )
        if dish.price_minor <= 0:
            problems.append(f"recipe {key!r} dish {dish.name!r} has non-positive price")

# every food type referenced anywhere must resolve to at least itself
unknown_fb = []
for ft in taxonomy.FOOD_TYPES:
    for step in taxonomy.resolve_food_types(ft):
        if step not in taxonomy.FOOD_TYPES and step not in taxonomy.FOOD_TYPES:
            unknown_fb.append((ft, step))
for ft, step in unknown_fb:
    problems.append(f"food type {ft!r} falls back to unknown {step!r}")

print()
if problems:
    print(f"PROBLEMS ({len(problems)}):")
    for problem in problems[:60]:
        print(" -", problem)
    sys.exit(1)

print(f"OK: {len(RECIPES)} recipes, all pools >= 40, no duplicate names,")
print(f"    all food types and tags valid. Total distinct dishes: "
      f"{sum(len(r.candidates()) for r in RECIPES.values())}")
