import asyncio
from sqlalchemy import text
from app.db.session import engine

async def m():
    async with engine.connect() as c:
        # Check menu_item_categories
        rows = (await c.execute(text('''
            select table_schema, table_name, column_name, ordinal_position
            from information_schema.columns
            where table_name = 'menu_item_categories'
            order by table_schema, ordinal_position
        '''))).all()
        print("=== menu_item_categories ===")
        for r in rows:
            print(f'  {r[0]}.{r[1]}: {r[2]} (pos {r[3]})')

        rows = (await c.execute(text('''
            select table_schema, table_name, column_name, ordinal_position
            from information_schema.columns
            where table_name = 'categories'
            order by table_schema, ordinal_position
        '''))).all()
        print("\n=== categories ===")
        for r in rows:
            print(f'  {r[0]}.{r[1]}: {r[2]} (pos {r[3]})')

asyncio.run(m())