from app.catalog.build import build_catalogue

cat = build_catalogue()
low = []
for r in cat.restaurants:
    for d in r.all_dishes:
        if d.price_minor < 1500:
            low.append((r.key, d.name, d.price_minor))
print("under 1500 minor:", len(low))
for row in low[:20]:
    print("  ", row)
print("min/max:", min(x[2] for x in low) if low else None)

from collections import Counter
print("distinct low prices:", Counter(x[2] for x in low).most_common(10))
