"""Check the built catalogue for invariants the brief cares about."""
from collections import Counter

from app.catalog.build import build_catalogue

cat = build_catalogue()
print("restaurants", len(cat.restaurants), "sections", cat.section_total, "dishes", cat.dish_total)

bad_secs = 0
bad_count = 0
dup_in_section = 0
dup_in_restaurant = 0
examples = []
for r in cat.restaurants:
    if not 5 <= len(r.sections) <= 8:
        bad_secs += 1
        print("BAD SECTION COUNT", r.key, len(r.sections))
    all_names = []
    for s in r.sections:
        if not 30 <= s.count <= 40:
            bad_count += 1
            print("BAD SECTION SIZE", r.key, s.title, s.count)
        names = [d.name for d in s.dishes]
        c = [n for n, k in Counter(names).items() if k > 1]
        if c:
            dup_in_section += 1
            examples.append((r.key, s.title, c[:3]))
        all_names += names
    c = [n for n, k in Counter(all_names).items() if k > 1]
    if c:
        dup_in_restaurant += 1
        if len(examples) < 40:
            examples.append(("ACROSS", r.key, c[:6]))

print("bad section count:", bad_secs)
print("bad section size:", bad_count)
print("sections with duplicate names:", dup_in_section)
print("restaurants with cross-section duplicate names:", dup_in_restaurant)
for e in examples[:40]:
    print("   ", e)

# price sanity
prices = [d.price_minor for r in cat.restaurants for d in r.all_dishes]
print("price range minor:", min(prices), max(prices), "distinct prices:", len(set(prices)))

# cuisine uniqueness / name uniqueness across restaurants
print("duplicate restaurant names:",
      [n for n, k in Counter(r.name for r in cat.restaurants).items() if k > 1])
print("duplicate cuisine strings:", len(set(r.cuisine for r in cat.restaurants)))
