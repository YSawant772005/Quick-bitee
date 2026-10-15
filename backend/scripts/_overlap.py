from app.catalog.recipes import RECIPES

c = {d.name for d in RECIPES["coolers"].candidates()}
m = {d.name for d in RECIPES["mocktails"].candidates()}
print("coolers", len(c), "mocktails", len(m), "overlap", len(c & m))
print(sorted(c & m))
