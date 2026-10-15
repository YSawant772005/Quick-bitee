import json
data = json.load(open(r'C:\Users\Dell\QuickBitee\backend\app\static\catalog\manifest.json'))
assets = data['assets']
for k, v in sorted(assets.items()):
    if 'pizza' in k.lower() or 'bbq' in k.lower():
        print(f'{k}: {v["file"]} ({v["origin"]})')