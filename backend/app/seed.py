import asyncio

from sqlalchemy import select

from app.core.logging import get_logger, setup_logging
from app.core.security import hash_password
from app.db.session import SessionFactory
from app.models.catalog import MenuItem, Restaurant
from app.models.users import User

logger = get_logger(__name__)

CUSTOMERS = [
    ("customer@quickbite.dev", "Customer#123"),
    ("customer2@quickbite.dev", "Customer#123"),
]
ADMIN = ("admin@quickbite.dev", "Admin#123")

CATALOG: list[dict] = [
    {
        "name": "Biryani Blues House",
        "description": "Authentic Hyderabadi dum biryani, slow-cooked overnight.",
        "cuisine": "Hyderabadi",
        "image": "rest-biryani.jpg",
        "items": [
            ("Hyderabadi Chicken Biryani", "Fragrant basmati layered with spiced chicken, served with raita.", 32000, "dish-chicken-biryani.jpg"),
            ("Veg Dum Biryani", "Seasonal vegetables and saffron rice sealed and slow-steamed.", 24000, "dish-veg-biryani.jpg"),
            ("Chicken 65 Biryani", "Fiery Chicken 65 tossed through classic dum biryani.", 34000, "dish-chicken65-biryani.jpg"),
            ("Mirchi ka Salan", "Roasted green chilli curry, the classic biryani side.", 12000, "dish-mirchi-ka-salan.jpg"),
            ("Double ka Meetha", "Bread pudding with saffron, cardamom and reduced milk.", 14000, "dish-double-ka-meetha.jpg"),
        ],
    },
    {
        "name": "Slice & Co. Pizzeria",
        "description": "Wood-fired sourdough pizzas from a Neapolitan oven.",
        "cuisine": "Italian",
        "image": "rest-pizza.jpg",
        "items": [
            ("Margherita di Bufala", "San Marzano tomato, buffalo mozzarella, basil, olive oil.", 29900, "dish-margherita.jpg"),
            ("Pepperoni Blast", "Double pepperoni, mozzarella, oregano, chilli honey drizzle.", 44900, "dish-pepperoni.jpg"),
            ("Farm House", "Mushroom, capsicum, onion, tomato, olives and mozzarella.", 39900, "dish-farmhouse.jpg"),
            ("Garlic Butter Breadsticks", "Oven-baked breadsticks with garlic butter and dip.", 14900, "dish-breadsticks.jpg"),
            ("Choco Lava Cake", "Molten dark chocolate centre, served warm.", 9900, "dish-lava-cake.jpg"),
        ],
    },
    {
        "name": "Burger Barn",
        "description": "Smashed patties, toasted brioche, hand-cut fries.",
        "cuisine": "American",
        "image": "rest-burger.jpg",
        "items": [
            ("Classic Cheeseburger", "Smashed beef patty, cheddar, house sauce, pickles.", 19900, "dish-cheeseburger.jpg"),
            ("Crispy Chicken Burger", "Buttermilk-fried chicken thigh, slaw, chipotle mayo.", 21900, "dish-crispy-chicken-burger.jpg"),
            ("Paneer Crunch Burger", "Crispy paneer, mint mayo, pickled onions.", 18900, "dish-paneer-burger.jpg"),
            ("Peri Peri Fries", "Hand-cut fries dusted with peri peri spice.", 12900, "dish-peri-fries.jpg"),
            ("Chocolate Thickshake", "Belgian chocolate, vanilla ice cream, whipped cream.", 17900, "dish-thickshake.jpg"),
        ],
    },
    {
        "name": "Dosa District",
        "description": "Crisp dosas, fluffy idlis and filter coffee since 1987.",
        "cuisine": "South Indian",
        "image": "rest-dosa.jpg",
        "items": [
            ("Masala Dosa", "Golden crisp dosa with spiced potato masala, sambar and chutneys.", 12000, "dish-masala-dosa.jpg"),
            ("Paneer Dosa", "Stuffed with crumbled paneer, onion and green chilli.", 16000, "dish-paneer-dosa.jpg"),
            ("Idli Sambar (3 pc)", "Steamed rice cakes with hot sambar and chutney.", 8000, "dish-idli.jpg"),
            ("Mysore Bonda (4 pc)", "Crisp fried spiced lentil dumplings with coconut chutney.", 9000, "dish-bonda.jpg"),
            ("Filter Coffee", "Strong decoction with frothed milk, served in a dabara.", 6000, "dish-filter-coffee.jpg"),
        ],
    },
    {
        "name": "Punjabi Tadka",
        "description": "Tandoor-fired North Indian classics with real desi ghee.",
        "cuisine": "North Indian",
        "image": "rest-punjabi.jpg",
        "items": [
            ("Butter Chicken + Naan", "Char-grilled chicken in silky tomato-fenugreek makhani gravy with butter naan.", 36000, "dish-butter-chicken.jpg"),
            ("Paneer Tikka Masala", "Smoky paneer tikka simmered in onion-tomato masala.", 32000, "dish-paneer-tikka.jpg"),
            ("Dal Makhani", "Black lentils slow-cooked 24 hours, finished with cream.", 26000, "dish-dal-makhani.jpg"),
            ("Amritsari Kulcha", "Stuffed kulcha with chole, onion and imli chutney.", 15000, "dish-kulcha.jpg"),
            ("Gulab Jamun (2 pc)", "Warm khoya dumplings in rose syrup.", 11000, "dish-gulab-jamun.jpg"),
        ],
    },
    {
        "name": "Wok This Way",
        "description": "Street-style Asian bowls tossed on screaming-hot woks.",
        "cuisine": "Asian",
        "image": "rest-asian.jpg",
        "items": [
            ("Hakka Noodles", "Smoky wok-tossed noodles with crunchy vegetables.", 21000, "dish-hakka-noodles.jpg"),
            ("Veg Manchurian", "Crisp vegetable dumplings in garlic-soy glaze.", 19000, "dish-manchurian.jpg"),
            ("Thai Basil Fried Rice", "Jasmine rice, Thai basil, bird's eye chilli.", 23000, "dish-thai-fried-rice.jpg"),
            ("Kimchi Ramen Bowl", "Rich broth, house kimchi, soft egg, scallions.", 28000, "dish-ramen.jpg"),
            ("Spring Rolls (6 pc)", "Hand-rolled, stuffed with glass noodles and vegetables.", 16000, "dish-spring-rolls.jpg"),
        ],
    },
    {
        "name": "Sugar Rush",
        "description": "Small-batch desserts, baked fresh every morning.",
        "cuisine": "Desserts",
        "image": "rest-dessert.jpg",
        "items": [
            ("New York Cheesecake", "Baked cheesecake with berry compote.", 24000, "dish-cheesecake.jpg"),
            ("Molten Choco Brownie", "Warm brownie with a molten core, vanilla ice cream.", 19000, "dish-brownie.jpg"),
            ("Tiramisu Cup", "Espresso-soaked ladyfingers, mascarpone clouds, cocoa.", 22000, "dish-tiramisu.jpg"),
            ("Mango Sundae", "Alphonso mango, vanilla scoops, toasted nuts.", 17000, "dish-mango-sundae.jpg"),
            ("Red Velvet Jar", "Layered red velvet and cream cheese frosting in a jar.", 21000, "dish-red-velvet.jpg"),
        ],
    },
    {
        "name": "Chai Sutta Café",
        "description": "Kadak chai, coolers and cafe sips brewed all day.",
        "cuisine": "Beverages",
        "image": "rest-chai.jpg",
        "items": [
            ("Kadak Chai", "Slow-brewed strong masala chai.", 5000, "dish-kadak-chai.jpg"),
            ("Cold Coffee", "Blended cold coffee with a vanilla kick.", 12000, "dish-cold-coffee.jpg"),
            ("Mango Lassi", "Thick yogurt lassi with alphonso pulp.", 11000, "dish-mango-lassi.jpg"),
            ("Fresh Lime Soda", "Sweet, salted or mixed — your call.", 7000, "dish-lime-soda.jpg"),
            ("Masala Shikanji", "Lemonade with chaat masala and mint.", 6000, "dish-shikanji.jpg"),
        ],
    },
]


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

            for entry in CATALOG:
                existing = (
                    await session.execute(select(Restaurant).where(Restaurant.name == entry["name"]))
                ).scalar_one_or_none()
                if existing is not None:
                    continue
                restaurant = Restaurant(
                    name=entry["name"],
                    description=entry["description"],
                    cuisine=entry["cuisine"],
                    image_url=f"/static/catalog/{entry['image']}",
                    available=True,
                )
                session.add(restaurant)
                await session.flush()
                for name, description, price_minor, image in entry["items"]:
                    session.add(
                        MenuItem(
                            restaurant_id=restaurant.id,
                            name=name,
                            description=description,
                            price_minor=price_minor,
                            currency="INR",
                            image_url=f"/static/catalog/{image}",
                            available=True,
                        )
                    )
    logger.info("seed completed: users=%d restaurants=%d", len(CUSTOMERS) + 1, len(CATALOG))


def main() -> None:
    setup_logging()
    asyncio.run(seed())


if __name__ == "__main__":
    main()
