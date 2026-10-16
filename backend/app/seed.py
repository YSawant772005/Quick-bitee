import asyncio
import hashlib

from sqlalchemy import select

from app.catalog import taxonomy
from app.catalog.ids import stable_id
from app.core.logging import get_logger, setup_logging
from app.core.security import hash_password
from app.db.session import SessionFactory
from app.models.catalog import Category, MenuItem, MenuItemCategory, Restaurant
from app.models.users import User

logger = get_logger(__name__)

CUSTOMERS = [
    ("customer@quickbite.dev", "Customer#123"),
    ("customer2@quickbite.dev", "Customer#123"),
]
ADMIN = ("admin@quickbite.dev", "Admin#123")

#: Safe, non-real fallbacks: this demo platform publishes no walk-in kitchens
#: and no real addresses, so we say exactly that instead of inventing one.
DEMO_ADDRESS = "Delivery-only demo kitchen - no walk-in address"
DEMO_HOURS = "11:00 AM - 11:00 PM, daily"

#: (name, description, price_minor, image, global category slugs)
CATALOG: list[dict] = [
    {
        "name": "Biryani Blues House",
        "description": "Authentic Hyderabadi dum biryani, slow-cooked overnight.",
        "cuisine": "Hyderabadi",
        "image": "rest-biryani.jpg",
        "items": [
            ("Hyderabadi Chicken Biryani", "Fragrant basmati layered with spiced chicken, served with raita.", 32000, "dish-chicken-biryani.jpg", ["biryani", "north-indian", "non-vegetarian"]),
            ("Veg Dum Biryani", "Seasonal vegetables and saffron rice sealed and slow-steamed.", 24000, "dish-veg-biryani.jpg", ["biryani", "vegetarian"]),
            ("Chicken 65 Biryani", "Fiery Chicken 65 tossed through classic dum biryani.", 34000, "dish-chicken65-biryani.jpg", ["biryani", "street-food", "non-vegetarian"]),
            ("Mirchi ka Salan", "Roasted green chilli curry, the classic biryani side.", 12000, "dish-mirchi-ka-salan.jpg", ["indian", "vegetarian"]),
            ("Double ka Meetha", "Bread pudding with saffron, cardamom and reduced milk.", 14000, "dish-double-ka-meetha.jpg", ["desserts", "vegetarian"]),
        ],
    },
    {
        "name": "Slice & Co. Pizzeria",
        "description": "Wood-fired sourdough pizzas from a Neapolitan oven.",
        "cuisine": "Italian",
        "image": "rest-pizza.jpg",
        "items": [
            ("Margherita di Bufala", "San Marzano tomato, buffalo mozzarella, basil, olive oil.", 29900, "dish-margherita.jpg", ["pizza", "italian", "vegetarian"]),
            ("Pepperoni Blast", "Double pepperoni, mozzarella, oregano, chilli honey drizzle.", 44900, "dish-pepperoni.jpg", ["pizza", "italian", "non-vegetarian"]),
            ("Farm House", "Mushroom, capsicum, onion, tomato, olives and mozzarella.", 39900, "dish-farmhouse.jpg", ["pizza", "italian", "vegetarian"]),
            ("Garlic Butter Breadsticks", "Oven-baked breadsticks with garlic butter and dip.", 14900, "dish-breadsticks.jpg", ["italian", "snacks", "vegetarian"]),
            ("Choco Lava Cake", "Molten dark chocolate centre, served warm.", 9900, "dish-lava-cake.jpg", ["desserts", "vegetarian"]),
        ],
    },
    {
        "name": "Burger Barn",
        "description": "Smashed patties, toasted brioche, hand-cut fries.",
        "cuisine": "American",
        "image": "rest-burger.jpg",
        "items": [
            ("Classic Cheeseburger", "Smashed beef patty, cheddar, house sauce, pickles.", 19900, "dish-cheeseburger.jpg", ["burgers", "non-vegetarian"]),
            ("Crispy Chicken Burger", "Buttermilk-fried chicken thigh, slaw, chipotle mayo.", 21900, "dish-crispy-chicken-burger.jpg", ["burgers", "non-vegetarian"]),
            ("Paneer Crunch Burger", "Crispy paneer, mint mayo, pickled onions.", 18900, "dish-paneer-burger.jpg", ["burgers", "vegetarian"]),
            ("Peri Peri Fries", "Hand-cut fries dusted with peri peri spice.", 12900, "dish-peri-fries.jpg", ["snacks", "vegetarian"]),
            ("Chocolate Thickshake", "Belgian chocolate, vanilla ice cream, whipped cream.", 17900, "dish-thickshake.jpg", ["milkshakes", "beverages", "vegetarian"]),
        ],
    },
    {
        "name": "Dosa District",
        "description": "Crisp dosas, fluffy idlis and filter coffee since 1987.",
        "cuisine": "South Indian",
        "image": "rest-dosa.jpg",
        "items": [
            ("Masala Dosa", "Golden crisp dosa with spiced potato masala, sambar and chutneys.", 12000, "dish-masala-dosa.jpg", ["south-indian", "vegetarian"]),
            ("Paneer Dosa", "Stuffed with crumbled paneer, onion and green chilli.", 16000, "dish-paneer-dosa.jpg", ["south-indian", "vegetarian"]),
            ("Idli Sambar (3 pc)", "Steamed rice cakes with hot sambar and chutney.", 8000, "dish-idli.jpg", ["south-indian", "vegetarian"]),
            ("Mysore Bonda (4 pc)", "Crisp fried spiced lentil dumplings with coconut chutney.", 9000, "dish-bonda.jpg", ["south-indian", "snacks", "vegetarian"]),
            ("Filter Coffee", "Strong decoction with frothed milk, served in a dabara.", 6000, "dish-filter-coffee.jpg", ["coffee", "hot-beverages", "south-indian", "vegetarian"]),
        ],
    },
    {
        "name": "Punjabi Tadka",
        "description": "Tandoor-fired North Indian classics with real desi ghee.",
        "cuisine": "North Indian",
        "image": "rest-punjabi.jpg",
        "items": [
            ("Butter Chicken + Naan", "Char-grilled chicken in silky tomato-fenugreek makhani gravy with butter naan.", 36000, "dish-butter-chicken.jpg", ["north-indian", "non-vegetarian"]),
            ("Paneer Tikka Masala", "Smoky paneer tikka simmered in onion-tomato masala.", 32000, "dish-paneer-tikka.jpg", ["north-indian", "indian", "vegetarian"]),
            ("Dal Makhani", "Black lentils slow-cooked 24 hours, finished with cream.", 26000, "dish-dal-makhani.jpg", ["north-indian", "vegetarian"]),
            ("Amritsari Kulcha", "Stuffed kulcha with chole, onion and imli chutney.", 15000, "dish-kulcha.jpg", ["north-indian", "vegetarian"]),
            ("Gulab Jamun (2 pc)", "Warm khoya dumplings in rose syrup.", 11000, "dish-gulab-jamun.jpg", ["desserts", "vegetarian"]),
        ],
    },
    {
        "name": "Wok This Way",
        "description": "Street-style Asian bowls tossed on screaming-hot woks.",
        "cuisine": "Asian",
        "image": "rest-asian.jpg",
        "items": [
            ("Hakka Noodles", "Smoky wok-tossed noodles with crunchy vegetables.", 21000, "dish-hakka-noodles.jpg", ["noodles", "indo-chinese", "vegetarian"]),
            ("Veg Manchurian", "Crisp vegetable dumplings in garlic-soy glaze.", 19000, "dish-manchurian.jpg", ["indo-chinese", "vegetarian"]),
            ("Thai Basil Fried Rice", "Jasmine rice, Thai basil, bird's eye chilli.", 23000, "dish-thai-fried-rice.jpg", ["chinese", "vegetarian"]),
            ("Kimchi Ramen Bowl", "Rich broth, house kimchi, soft egg, scallions.", 28000, "dish-ramen.jpg", ["noodles", "non-vegetarian"]),
            ("Spring Rolls (6 pc)", "Hand-rolled, stuffed with glass noodles and vegetables.", 16000, "dish-spring-rolls.jpg", ["wraps-rolls", "vegetarian"]),
        ],
    },
    {
        "name": "Sugar Rush",
        "description": "Small-batch desserts, baked fresh every morning.",
        "cuisine": "Desserts",
        "image": "rest-dessert.jpg",
        "items": [
            ("New York Cheesecake", "Baked cheesecake with berry compote.", 24000, "dish-cheesecake.jpg", ["desserts", "cakes-bakery", "vegetarian"]),
            ("Molten Choco Brownie", "Warm brownie with a molten core, vanilla ice cream.", 19000, "dish-brownie.jpg", ["desserts", "vegetarian"]),
            ("Tiramisu Cup", "Espresso-soaked ladyfingers, mascarpone clouds, cocoa.", 22000, "dish-tiramisu.jpg", ["desserts", "cakes-bakery", "vegetarian"]),
            ("Mango Sundae", "Alphonso mango, vanilla scoops, toasted nuts.", 17000, "dish-mango-sundae.jpg", ["ice-cream", "desserts", "vegetarian"]),
            ("Red Velvet Jar", "Layered red velvet and cream cheese frosting in a jar.", 21000, "dish-red-velvet.jpg", ["desserts", "cakes-bakery", "vegetarian"]),
        ],
    },
    {
        "name": "Chai Sutta Café",
        "description": "Kadak chai, coolers and cafe sips brewed all day.",
        "cuisine": "Beverages",
        "image": "rest-chai.jpg",
        "items": [
            ("Kadak Chai", "Slow-brewed strong masala chai.", 5000, "dish-kadak-chai.jpg", ["tea", "hot-beverages", "beverages", "vegetarian"]),
            ("Cold Coffee", "Blended cold coffee with a vanilla kick.", 12000, "dish-cold-coffee.jpg", ["coffee", "cold-beverages", "beverages", "vegetarian"]),
            ("Mango Lassi", "Thick yogurt lassi with alphonso pulp.", 11000, "dish-mango-lassi.jpg", ["beverages", "vegetarian"]),
            ("Fresh Lime Soda", "Sweet, salted or mixed — your call.", 7000, "dish-lime-soda.jpg", ["cold-beverages", "beverages", "vegetarian"]),
            ("Masala Shikanji", "Lemonade with chaat masala and mint.", 6000, "dish-shikanji.jpg", ["beverages", "cold-beverages", "vegetarian"]),
        ],
    },
]


def _eta_window(name: str) -> tuple[int, int]:
    """Deterministic 20-35 minute estimate, same rule as the migration."""
    digest = int(hashlib.md5(name.encode("utf-8")).hexdigest()[:8], 16)
    low = 20 + (digest % 4) * 5
    return low, low + 15


async def _ensure_global_categories(session) -> dict[str, str]:
    """Create every global category once, keyed by slug.

    Uses the same ``stable_id`` convention as ``scripts/seed_catalogue.py`` so
    both seeding paths upsert the same rows instead of fighting over the
    unique (kind, slug) index.
    """
    ids: dict[str, str] = {}
    for slug, name, description, thumb, sort_order in taxonomy.GLOBAL_CATEGORIES:
        cat_id = stable_id("category", "global", slug)
        existing = (
            await session.execute(
                select(Category).where(Category.kind == "global", Category.slug == slug)
            )
        ).scalar_one_or_none()
        if existing is None:
            session.add(
                Category(
                    id=cat_id,
                    kind="global",
                    slug=slug,
                    name=name,
                    description=description,
                    image_url=f"/static/catalog/{thumb}.jpg",
                    sort_order=sort_order,
                )
            )
            await session.flush()
            ids[slug] = cat_id
        else:
            ids[slug] = existing.id
    return ids


async def _ensure_section(session, restaurant: Restaurant) -> Category:
    """The single menu section (``kind='menu'``) for a legacy restaurant."""
    existing = (
        await session.execute(
            select(Category).where(
                Category.kind == "menu",
                Category.restaurant_id == restaurant.id,
                Category.slug == "menu",
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        return existing
    section = Category(
        id=stable_id("category", restaurant.id, "menu"),
        kind="menu",
        slug="menu",
        name="Full menu",
        restaurant_id=restaurant.id,
        sort_order=0,
    )
    session.add(section)
    await session.flush()
    return section


async def _ensure_links(
    session,
    dish: MenuItem,
    global_ids: list[str],
    section_id: str,
) -> None:
    """Attach the dish's category links, skipping any that already exist."""
    current = set(
        (
            await session.execute(
                select(MenuItemCategory.category_id).where(
                    MenuItemCategory.menu_item_id == dish.id
                )
            )
        ).scalars()
    )
    for category_id in [*global_ids, section_id]:
        if category_id not in current:
            session.add(
                MenuItemCategory(menu_item_id=dish.id, category_id=category_id)
            )


async def seed() -> None:
    async with SessionFactory() as session:
        async with session.begin():
            for email, password in CUSTOMERS + [ADMIN]:
                existing = (
                    await session.execute(select(User).where(User.email == email))
                ).scalar_one_or_none()
                if existing is None:
                    role = "admin" if email == ADMIN[0] else "customer"
                    session.add(User(email=email, password_hash=hash_password(password), role=role))

            global_ids = await _ensure_global_categories(session)

            for entry in CATALOG:
                low, high = _eta_window(entry["name"])
                restaurant = (
                    await session.execute(
                        select(Restaurant).where(Restaurant.name == entry["name"])
                    )
                ).scalar_one_or_none()
                if restaurant is None:
                    restaurant = Restaurant(
                        name=entry["name"],
                        description=entry["description"],
                        cuisine=entry["cuisine"],
                        image_url=f"/static/catalog/{entry['image']}",
                        available=True,
                        address=DEMO_ADDRESS,
                        opening_hours=DEMO_HOURS,
                        eta_minutes_min=low,
                        eta_minutes_max=high,
                    )
                    session.add(restaurant)
                    await session.flush()
                else:
                    # Idempotent backfill for rows seeded before the detail
                    # columns existed. Never overwrites a configured value.
                    if not restaurant.address:
                        restaurant.address = DEMO_ADDRESS
                    if not restaurant.opening_hours:
                        restaurant.opening_hours = DEMO_HOURS
                    if restaurant.eta_minutes_min == 25 and restaurant.eta_minutes_max == 45:
                        restaurant.eta_minutes_min, restaurant.eta_minutes_max = low, high

                section = await _ensure_section(session, restaurant)

                for name, description, price_minor, image, tags in entry["items"]:
                    dish = (
                        await session.execute(
                            select(MenuItem).where(
                                MenuItem.restaurant_id == restaurant.id,
                                MenuItem.name == name,
                            )
                        )
                    ).scalar_one_or_none()
                    if dish is None:
                        dish = MenuItem(
                            restaurant_id=restaurant.id,
                            name=name,
                            description=description,
                            price_minor=price_minor,
                            currency="INR",
                            image_url=f"/static/catalog/{image}",
                            available=True,
                        )
                        session.add(dish)
                        await session.flush()
                    wanted = [
                        global_ids[slug]
                        for slug in tags
                        if slug in global_ids  # never invent unknown taxonomy
                    ]
                    await _ensure_links(session, dish, wanted, section.id)

    logger.info("seed completed: users=%d restaurants=%d", len(CUSTOMERS) + 1, len(CATALOG))


def main() -> None:
    setup_logging()
    asyncio.run(seed())


if __name__ == "__main__":
    main()
