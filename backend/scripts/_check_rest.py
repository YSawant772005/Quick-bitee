import json
data = json.load(open(r'C:\Users\Dell\QuickBitee\backend\app\static\catalog\manifest.json'))
assets = data['assets']
for k, v in sorted(assets.items()):
    if v['file'].startswith('rest-'):
        print(f'{k}: {v["file"]}')