"""Assemble the full in-memory catalogue: concepts -> sections -> dishes.

Pure and deterministic — no database, no network. The seeder
(``scripts/seed_catalogue.py``) and the image pipeline both consume the output
of :func:`build_catalogue`, which is why the same run always produces the same
dish names, prices, photo choices and primary keys.
"""

from __future__ import annotations

import zlib
from dataclasses import dataclass, field

from app.catalog import taxonomy
from app.catalog.concepts import CONCEPTS, Concept, Section
from app.catalog.dishes import Dish, bind_food_types
from app.catalog.recipes import RECIPES

#: Dishes offered in a single menu section. The brief asks for 30-40.
SECTION_MIN = 30
SECTION_MAX = 40

#: Coprime-ish step so two restaurants drawing on the same recipe get
#: overlapping-but-not-identical slices of the recipe's pool.
_ROTATION_STEP = 13


def _h(text: str) -> int:
    return zlib.crc32(text.encode("utf-8"))


@dataclass
class BuiltSection:
    """One menu section of one restaurant, already filled with dishes."""

    title: str
    recipe_key: str
    dishes: list[Dish] = field(default_factory=list)
    #: How many of ``dishes`` were already on an earlier section of the same
    #: menu. Always 0 unless a recipe runs out of fresh names.
    reused: int = 0

    @property
    def slug(self) -> str:
        return slugify(self.title)

    @property
    def count(self) -> int:
        return len(self.dishes)


@dataclass
class BuiltRestaurant:
    key: str
    name: str
    cuisine: str
    description: str
    cover_food_type: str
    price_tier: int
    sections: list[BuiltSection] = field(default_factory=list)

    @property
    def dish_count(self) -> int:
        return sum(s.count for s in self.sections)

    @property
    def all_dishes(self) -> list[Dish]:
        return [d for s in self.sections for d in s.dishes]


@dataclass
class Catalogue:
    restaurants: list[BuiltRestaurant] = field(default_factory=list)

    # -- derived views ----------------------------------------------------
    @property
    def dish_total(self) -> int:
        return sum(r.dish_count for r in self.restaurants)

    @property
    def section_total(self) -> int:
        return sum(len(r.sections) for r in self.restaurants)

    def global_category_counts(self) -> dict[str, int]:
        """Distinct dishes per global category (a dish in two categories counts once in each)."""
        counts: dict[str, int] = {slug: 0 for slug in taxonomy.GLOBAL_CATEGORY_SLUGS}
        seen: dict[str, set[tuple[str, str]]] = {slug: set() for slug in counts}
        for restaurant in self.restaurants:
            for dish in restaurant.all_dishes:
                for tag in dish.tags:
                    if tag in seen:
                        seen[tag].add((restaurant.key, dish.name))
        for slug, keys in seen.items():
            counts[slug] = len(keys)
        return counts

    def food_types_used(self) -> dict[str, int]:
        """How many dish slots resolve to each food type (post-fallback)."""
        from collections import Counter

        counter: Counter[str] = Counter()
        for restaurant in self.restaurants:
            for dish in restaurant.all_dishes:
                counter[resolve_food(dish.food_type)] += 1
        return dict(counter)

    def all_food_types(self) -> set[str]:
        """Every food type referenced directly by a dish (before fallback)."""
        out: set[str] = set()
        for restaurant in self.restaurants:
            for dish in restaurant.all_dishes:
                out.add(dish.food_type)
            out.add(restaurant.cover_food_type)
        for slug, _name, _desc, thumb, _order in taxonomy.GLOBAL_CATEGORIES:
            out.add(thumb)
        return out


def slugify(text: str) -> str:
    """URL-safe slug, stable across runs and platforms."""
    out: list[str] = []
    for ch in text.lower().strip():
        if ch.isalnum():
            out.append(ch)
        elif out and out[-1] != "-":
            out.append("-")
    slug = "".join(out).strip("-")
    return slug[:80]


def resolve_food(food_type: str) -> str:
    """First food type in ``food_type``'s fallback chain that is actually known."""
    for candidate in taxonomy.resolve_food_types(food_type):
        if candidate in taxonomy.FOOD_TYPES:
            return candidate
    return food_type


def section_dish_count(concept_key: str, title: str) -> int:
    """Deterministic 30-40 count for one section."""
    span = SECTION_MAX - SECTION_MIN + 1
    return SECTION_MIN + _h(f"{concept_key}|{title}") % span


VEG_SLUG = taxonomy.VEGETARIAN_SLUG
NON_VEG_SLUG = taxonomy.NON_VEGETARIAN_SLUG
_DIET_SLUGS = (VEG_SLUG, NON_VEG_SLUG)


def _with_diet_tags(dishes: list[Dish]) -> list[Dish]:
    """Re-decide the veg/non-veg tags for each dish from its own ``veg`` flag.

    Recipe pools deliberately mix both sides of the menu — ``noodles`` has
    chicken and tofu variants, ``burgers`` has a chicken patty next to a paneer
    one — so a recipe-level diet tag can only ever be half true. Dropping it
    here and re-deriving per dish is what keeps the customer's "Vegetarian"
    browse list free of chicken.
    """
    out: list[Dish] = []
    for dish in dishes:
        tags = tuple(t for t in dish.tags if t not in _DIET_SLUGS)
        tags = tags + ((VEG_SLUG,) if dish.veg else (NON_VEG_SLUG,))
        out.append(
            Dish(
                name=dish.name,
                description=dish.description,
                price_minor=dish.price_minor,
                food_type=dish.food_type,
                veg=dish.veg,
                tags=tags,
            )
        )
    return out


def _pick(
    pool: list[Dish],
    count: int,
    offset: int,
    used: set[str],
) -> tuple[list[Dish], int]:
    """Take ``count`` distinct dishes for one section.

    Names already served elsewhere in the same restaurant are skipped first, so
    a house menu does not list the same dish twice; only if the recipe cannot
    supply enough *new* names are earlier ones reused. Returns the dishes and
    how many had to be reused.
    """
    rotated = pool[offset:] + pool[:offset] if offset else list(pool)
    picked: list[Dish] = []
    picked_names: set[str] = set()

    for dish in rotated:
        if len(picked) == count:
            break
        if dish.name in used or dish.name in picked_names:
            continue
        picked.append(dish)
        picked_names.add(dish.name)

    reused = 0
    if len(picked) < count:
        for dish in rotated:
            if len(picked) == count:
                break
            if dish.name in picked_names:
                continue
            picked.append(dish)
            picked_names.add(dish.name)
            reused += 1
    return picked, reused


def build_catalogue() -> Catalogue:
    bind_food_types(set(taxonomy.FOOD_TYPES))

    catalogue = Catalogue()
    #: recipe key -> how many sections have drawn from it so far, used to walk
    #: each subsequent user to a different part of the pool.
    draws: dict[str, int] = {}

    for concept in CONCEPTS:
        restaurant = BuiltRestaurant(
            key=concept.key,
            name=concept.name,
            cuisine=concept.cuisine,
            description=concept.description,
            cover_food_type=concept.cover_food_type,
            price_tier=concept.price_tier,
        )
        used: set[str] = set()
        for section in concept.sections:
            recipe = RECIPES[section.recipe]
            count = section_dish_count(concept.key, section.title)
            pool = recipe.candidates()
            pool_len = len(pool)
            rotation = (draws.get(section.recipe, 0) * _ROTATION_STEP) % pool_len
            draws[section.recipe] = draws.get(section.recipe, 0) + 1

            picked, reused = _pick(pool, count, rotation, used)
            dishes = _with_diet_tags(picked)
            used.update(d.name for d in dishes)
            restaurant.sections.append(
                BuiltSection(
                    title=section.title,
                    recipe_key=section.recipe,
                    dishes=list(dishes),
                    reused=reused,
                )
            )
        catalogue.restaurants.append(restaurant)

    return catalogue


# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------


def report(catalogue: Catalogue) -> str:
    lines: list[str] = []
    lines.append(
        f"restaurants: {len(catalogue.restaurants)}  "
        f"sections: {catalogue.section_total}  "
        f"dishes: {catalogue.dish_total}"
    )
    lines.append("")

    lines.append(f"{'restaurant':30} {'cuisine':16} {'secs':>4} {'dishes':>6}  sections")
    lines.append("-" * 110)
    for r in catalogue.restaurants:
        titles = ", ".join(f"{s.title}({s.count})" for s in r.sections)
        lines.append(
            f"{r.name[:30]:30} {r.cuisine[:16]:16} {len(r.sections):>4} "
            f"{r.dish_count:>6}  {titles}"
        )

    lines.append("")
    lines.append("global category coverage (distinct dishes):")
    counts = catalogue.global_category_counts()
    short = []
    for slug, _name, _desc, _thumb, _order in sorted(
        taxonomy.GLOBAL_CATEGORIES, key=lambda row: row[4]
    ):
        n = counts.get(slug, 0)
        flag = "" if n >= 40 else "   <-- SHORT"
        if n < 40:
            short.append((slug, n))
        lines.append(f"  {slug:22} {n:>5}{flag}")

    lines.append("")
    if short:
        lines.append(f"SHORT CATEGORIES ({len(short)}): {short}")
    else:
        lines.append("all global categories have >= 40 distinct dishes")

    lines.append("")
    unused = [
        slug
        for slug, _n, _d, _t, _o in taxonomy.GLOBAL_CATEGORIES
        if counts.get(slug, 0) == 0
    ]
    lines.append(f"EMPTY CATEGORIES: {unused or 'none'}")

    lines.append("")
    food = catalogue.food_types_used()
    lines.append(f"distinct food types referenced by dishes: {len(catalogue.all_food_types())}")
    lines.append(f"food types after fallback resolution:    {len(food)}")
    return "\n".join(lines)


if __name__ == "__main__":
    print(report(build_catalogue()))
