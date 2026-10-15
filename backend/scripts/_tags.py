from app.catalog.recipes import RECIPES

for k, r in sorted(RECIPES.items()):
    print(f"{k:26} {r.title:24} {','.join(r.tags)}")
