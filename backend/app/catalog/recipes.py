"""Named recipes — reusable menu sections.

A *recipe* is one menu section of a restaurant (``Starters``, ``Breads``…).
It knows how to produce a large, *distinct* pool of plausible dishes; each
restaurant then takes a deterministic slice of that pool, so two biryani houses
share a vocabulary but not an identical menu.

The section title shown in the UI lives on the :class:`Recipe`; the restaurant
concept may rename it.
"""

from __future__ import annotations

from app.catalog.dishes import _BASES, ExplicitItem, Recipe, _METHODS, _price_for  # noqa: F401

# ---------------------------------------------------------------------------
# helpers for building groups
# ---------------------------------------------------------------------------

_VEG_STARTER_BASES = (
    "paneer",
    "mushroom",
    "babycorn",
    "aloo",
    "soya",
    "cheese",
    "gobi",
    "corn",
)

_NONVEG_STARTER_BASES = ("chicken", "mutton", "fish", "prawn", "egg", "keema")


def _g(bases: tuple[str, ...], methods: tuple[str, ...]) -> tuple[tuple[str, ...], tuple[str, ...]]:
    return (bases, methods)


# ---------------------------------------------------------------------------
# explicit pools (items that read better hand-written)
# ---------------------------------------------------------------------------

_BREADS: tuple[ExplicitItem, ...] = tuple(
    # Pool literals are written in rupees for readability; the schema stores
    # minor units (paise), so convert once here.
    ExplicitItem(n, d, f, v, p * 100)
    for n, d, f, v, p in [
        ("Plain Naan", "Soft leavened bread straight from the tandoor.", "naan", True, 55),
        ("Garlic Naan", "Naan pressed with minced garlic and coriander.", "garlic-naan", True, 85),
        ("Butter Naan", "Tandoori naan finished with a brush of white butter.", "butter-naan", True, 75),
        ("Cheese Naan", "Stuffed with molten cheese and a hint of green chilli.", "cheese-naan", True, 135),
        ("Keema Naan", "Stuffed with spiced minced mutton and fried onion.", "keema-naan", False, 155),
        ("Paneer Kulcha", "Stuffed with crumbled paneer, ginger and kasuri methi.", "kulcha", True, 135),
        ("Amritsari Kulcha", "Crisp-bottomed, potato-stuffed and topped with butter.", "kulcha", True, 115),
        ("Aloo Paratha", "Stuffed with spiced potato, served with curd and butter.", "paratha", True, 105),
        ("Paneer Paratha", "Stuffed with spiced paneer and fresh coriander.", "paratha", True, 125),
        ("Gobi Paratha", "Stuffed with ajwain-seasoned cauliflower.", "paratha", True, 115),
        ("Onion Paratha", "Stuffed with onion, green chilli and coriander.", "paratha", True, 105),
        ("Laccha Paratha", "Hand-layered whole-wheat paratha, flaky and soft.", "laccha-paratha", True, 95),
        ("Tandoori Roti", "Whole-wheat roti blistered against the tandoor wall.", "tandoori-roti", True, 45),
        ("Butter Roti", "Soft tandoori roti with a swipe of butter.", "roti", True, 55),
        ("Missi Roti", "Besan and spice flatbread with ajwain and methi.", "missi-roti", True, 65),
        ("Rumali Roti", "Paper-thin handkerchief roti, folded and served warm.", "rumali-roti", True, 70),
        ("Puri", "Two puffed puris, best eaten hot.", "puri", True, 45),
        ("Bhatura", "Deep-fried leavened bread, served with chole.", "bhatura", True, 85),
        ("Steamed Rice", "Long-grain basmati steamed and finished with ghee.", "rice-bowl", True, 90),
        ("Jeera Rice", "Basmati tossed with ghee and toasted cumin.", "jeera-rice", True, 110),
        ("Veg Fried Rice", "Wok-tossed rice with shredded vegetables and soy.", "fried-rice", True, 145),
        ("Egg Fried Rice", "Rice tossed with egg, spring onion and soy.", "fried-rice-egg", False, 160),
        ("Chicken Fried Rice", "Rice tossed with chicken, egg and burnt garlic.", "fried-rice-chicken", False, 180),
        ("Veg Hakka Noodles", "Hakka-style noodles with vegetables and vinegar.", "noodles-veg", True, 145),
        ("Egg Hakka Noodles", "Noodles wok-tossed with egg and spring onion.", "noodles-egg", False, 160),
        ("Chicken Hakka Noodles", "Noodles with chicken, cabbage and soy.", "noodles-chicken", False, 180),
        ("Paneer Chilli", "Cottage cheese tossed with chilli, garlic and capsicum.", "chilli-paneer", True, 175),
        ("Veg Manchurian", "Vegetable dumplings in a glossy garlic-soy sauce.", "manchurian", True, 155),
        ("Chicken Manchurian", "Chicken dumplings in a house-made Manchurian sauce.", "manchurian", False, 185),
        ("Crispy Corn", "Sweet corn fried crisp with curry leaf and chilli.", "crispy-corn", True, 165),
        ("Honey Chilli Potato", "Twice-fried potato glazed with honey and sesame.", "honey-chilli-potato", True, 165),
        ("French Fries", "Salted potato fries, fried to order.", "french-fries", True, 110),
        ("Peri Peri Fries", "Fries dusted with peri peri masala.", "fries-plain", True, 135),
        ("Loaded Cheese Fries", "Fries smothered in cheese sauce and jalapeño.", "loaded-fries", True, 175),
        ("Mozzarella Sticks", "Breaded mozzarella, fried until the cheese runs.", "mozzarella-sticks", True, 185),
        ("Garlic Bread", "Toasted bread with garlic butter and herbs.", "garlic-bread", True, 115),
        ("Cheesy Garlic Bread", "Garlic bread loaded with melted mozzarella.", "garlic-bread", True, 155),
        ("Bread Sticks", "Oven-baked sticks with a parmesan finish.", "breadsticks", True, 105),
        ("Soup Stick", "Crisp breadsticks for the table.", "breadsticks", True, 85),
        ("Dinner Roll", "Soft buttered roll, served warm.", "bread-bun", True, 60),
    ]
)

_SOUPS: tuple[ExplicitItem, ...] = tuple(
    # Pool literals are written in rupees for readability; the schema stores
    # minor units (paise), so convert once here.
    ExplicitItem(n, d, f, v, p * 100)
    for n, d, f, v, p in [
        ("Manchow Soup", "Dark, peppery broth with fried noodles on top.", "manchow-soup", True, 130),
        ("Hot & Sour Soup", "Sharp with vinegar and white pepper, thick and warming.", "hot-soup", True, 130),
        ("Sweet Corn Soup", "Silky sweet-corn broth, vegetarian.", "corn-sweet-soup", True, 120),
        ("Chicken Manchow Soup", "Chicken Manchow with fried noodle crisps.", "manchow-soup", False, 150),
        ("Chicken Hot & Sour", "Chicken hot and sour with shredded meat.", "hot-soup", False, 150),
        ("Wonton Soup", "Chicken wontons floating in a clear broth.", "wonton-soup", False, 160),
        ("Veg Wonton Soup", "Vegetable wontons in a light clear broth.", "wonton-soup", True, 140),
        ("Thukpa", "Himalayan noodle soup with vegetables and timur.", "thukpa", True, 160),
        ("Chicken Thukpa", "Tibetan noodle soup with chicken and greens.", "thukpa-noodle", False, 180),
        ("Tomato Basil Soup", "Roasted tomato finished with basil and cream.", "soup-tomato", True, 140),
        ("Cream of Mushroom", "Velvety mushroom soup with croutons.", "soup-mushroom", True, 150),
        ("Cream of Vegetable", "Smooth puréed vegetable soup.", "soup-bowl", True, 140),
        ("Lemon Coriander Soup", "Clear, sharp and finished with coriander.", "soup-bowl", True, 120),
        ("Minestrone", "Italian vegetable soup with beans and pasta.", "soup-bowl", True, 165),
        ("Chicken Clear Soup", "Slow-simmered chicken consommé.", "soup-bowl", False, 140),
        ("Egg Drop Soup", "Silken broth with ribbons of egg and pepper.", "soup-bowl", False, 130),
        ("Miso Soup", "Fermented soy broth with tofu and wakame.", "miso-soup", True, 150),
        ("Tom Yum Soup", "Thai hot-and-sour soup with lemongrass and galangal.", "tom-yum", True, 175),
        ("Chicken Tom Yum", "Tom yum with chicken and straw mushrooms.", "tom-yum", False, 195),
        ("Prawn Tom Yum", "Tom yum with prawns and kaffir lime leaf.", "tom-yum", False, 220),
        ("Pepper Soup", "Cracked pepper broth with ginger and garlic.", "soup-bowl", True, 130),
        ("Broccoli Soup", "Thick broccoli soup with a cheddar finish.", "soup-mushroom", True, 155),
        ("Spinach Soup", "Puréed spinach with a touch of cream.", "soup-bowl", True, 150),
        ("Mixed Vegetable Clear", "Clear broth with finely diced vegetables.", "soup-bowl", True, 125),
        ("Fish Chowder", "Thick fish soup with potato and celery.", "soup-bowl", False, 210),
        ("Lentil Soup", "Slow-cooked lentils with cumin tempering.", "dal", True, 140),
        ("Rasam", "Peppery tamarind broth with curry leaf and coriander.", "rasam", True, 90),
        ("Sambar", "Toor dal and vegetables simmered with sambar masala.", "sambar", True, 100),
        ("Chicken Corn Soup", "Sweet corn and shredded chicken.", "corn-sweet-soup", False, 150),
        ("Veg Clear Soup", "Light vegetable broth, no thickener.", "soup-bowl", True, 115),
        ("Thai Vegetable Soup", "Coconut-tinged Thai soup with galangal.", "tom-yum", True, 170),
        ("Kimchi Jjigae", "Spicy Korean stew with tofu and pork.", "kimchi", False, 220),
        ("Budae Jjigae", "Korean army stew with vegetables and noodles.", "kimchi", False, 240),
        ("Pozole", "Mexican hominy soup with herbs and lime.", "soup-bowl", True, 190),
        ("Tortilla Soup", "Mexican tomato broth with tortilla crisps.", "soup-tomato", True, 175),
        ("Clam Chowder", "Creamy chowder with potato and celery.", "soup-bowl", False, 230),
        ("Pumpkin Soup", "Roasted pumpkin finished with nutmeg.", "soup-tomato", True, 155),
        ("Carrot & Ginger Soup", "Sweet carrot warmed with fresh ginger.", "soup-tomato", True, 150),
        ("French Onion Soup", "Caramelised onion broth with a gruyère crouton.", "soup-bowl", True, 185),
        ("Gazpacho", "Chilled Spanish tomato and pepper soup.", "soup-tomato", True, 160),
        ("Egg Drop Manchow", "Manchow broth finished with egg ribbons.", "manchow-soup", False, 145),
        ("Pepper Chicken Soup", "Pepper-forward broth with shredded chicken.", "soup-bowl", False, 155),
        ("Spinach & Corn Soup", "Creamy spinach with sweet corn kernels.", "soup-mushroom", True, 150),
        ("Vegetable Barley Soup", "Hearty barley with diced vegetables.", "soup-bowl", True, 160),
        ("Mushroom Broth", "Clear mushroom broth with thyme.", "soup-mushroom", True, 140),
        ("Coconut Chicken Soup", "Thai coconut broth with chicken and lime leaf.", "thai-curry", False, 200),
        ("Ramen Broth", "Twelve-hour pork and soy broth with spring onion.", "ramen", False, 240),
        ("Udon Broth", "Dashi broth with thick udon and scallion.", "udon", True, 210),
        ("Laksa", "Coconut curry noodle soup with tofu and bean sprouts.", "rice-noodles", True, 220),
    ]
)

_CHAAT: tuple[ExplicitItem, ...] = tuple(
    # Pool literals are written in rupees for readability; the schema stores
    # minor units (paise), so convert once here.
    ExplicitItem(n, d, f, v, p * 100)
    for n, d, f, v, p in [
        ("Samosa Chaat", "Crushed samosas drenched in chutneys and curd.", "chaat-mix", True, 120),
        ("Papdi Chaat", "Crisp wafers, potato, curd and three chutneys.", "sev-puri", True, 110),
        ("Pani Puri", "Six puris with spiced water and potato filling.", "pani-puri", True, 60),
        ("Dahi Puri", "Stuffed puris drowned in sweet curd and chutney.", "dahi-puri", True, 90),
        ("Sev Puri", "Flat puris layered with potato, chutney and sev.", "sev-puri", True, 80),
        ("Bhel Puri", "Puffed rice, vegetables and chutneys, tossed to order.", "bhel-puri", True, 70),
        ("Raj Kachori", "A giant kachori filled with four kinds of chaat.", "kachori", True, 150),
        ("Dahi Vada", "Soft lentil dumplings soaked in seasoned curd.", "dahi-vada", True, 100),
        ("Aloo Tikki Chaat", "Seared potato patty with chutneys and whipped curd.", "tikki", True, 90),
        ("Ragda Pattice", "White peas curry over griddled potato patties.", "ragda", True, 110),
        ("Pav Bhaji", "Mashed vegetable bhaji with butter-toasted pav.", "pav-bhaji", True, 130),
        ("Cheese Pav Bhaji", "Pav bhaji finished with a cheese slab.", "pav-bhaji", True, 160),
        ("Vada Pav", "The Mumbai classic with dry garlic chutney.", "vada-pav", True, 40),
        ("Misal Pav", "Spicy sprouted moth curry with farsan and pav.", "misal", True, 120),
        ("Dabeli", "Spiced potato in a pav with pomegranate and sev.", "chaat-mix", True, 60),
        ("Kachori Chaat", "Crushed kachori with curd, chutney and sev.", "kachori", True, 100),
        ("Samosa (2 pcs)", "Two crisp samosas with tamarind and mint chutney.", "samosa", True, 50),
        ("Poha", "Flattened rice with peanuts, curry leaf and lemon.", "poha", True, 50),
        ("Upma", "Roasted semolina with mustard, curry leaf and vegetables.", "upma", True, 50),
        ("Idli Chaat", "Fried idli tossed with chutneys and sev.", "idli-fry", True, 110),
        ("Momos Chaat", "Fried momos broken into a chaat with three chutneys.", "momo-fried", True, 130),
        ("Chaat Platter", "A sampler of four chaats for the table.", "chaat-mix", True, 260),
        ("Bhel (Jumbo)", "A large portion of bhel puri, tossed to order.", "bhel-puri", True, 110),
        ("Pani Puri (Refill)", "An extra round of spiced water and puris.", "pani-puri", True, 40),
        ("Sev Tameta", "Gujarati sweet-sour tomato with thick sev.", "chaat-mix", True, 110),
        ("Khandvi", "Gram-flour rolls with coconut and mustard tempering.", "chaat-mix", True, 100),
        ("Dhokla", "Steamed fermented gram-flour cake with curry leaf.", "chaat-mix", True, 90),
        ("Khaman", "Spongy khaman with green chutney and sev.", "chaat-mix", True, 90),
        ("Handvo", "Baked rice-and-lentil cake with sesame crust.", "chaat-mix", True, 110),
        ("Thepla (3 pcs)", "Methi theplas with curd and pickles.", "paratha", True, 90),
        ("Khakhra", "Crisp roasted wheat cracker with masala.", "breadsticks", True, 60),
        ("Fafda & Jalebi", "The classic Gujarati pairing, served together.", "jalebi", True, 130),
        ("Muthia", "Steamed and tempered chickpea-flour rolls.", "chaat-mix", True, 100),
        ("Jhaal Muri", "Bengali puffed rice with mustard oil and peanuts.", "bhel-puri", True, 70),
        ("Ghugni Chaat", "Black pea curry with onion, chutney and sev.", "chaat-mix", True, 100),
        ("Churmur", "Bengali street chaat of crushed puri and potato.", "chaat-mix", True, 80),
        ("Alu Kabli", "Bengali chickpea and potato chaat with tamarind.", "chaat-mix", True, 90),
        ("Kulfi Falooda", "Kulfi on falooda with rose syrup and basil seeds.", "falooda", True, 150),
        ("Ragda Samosa", "Samosa drowned in ragda with chutneys.", "ragda", True, 130),
        ("Cheese Balls", "Breaded cheese balls with a molten centre.", "cheese-bites", True, 170),
        ("Nachos Chaat", "Nachos refashioned with beans, salsa and cheese.", "nachos-cheese", True, 180),
        ("Tikki Masala Chaat", "Two tikkis in a sharp masala gravy.", "tikki-chaat", True, 120),
        ("Pav Bhaji (No Butter)", "Pav bhaji cooked without butter on request.", "pav-bhaji", True, 120),
        ("Ragda Pattice (Dry)", "Dry ragda pattice without extra gravy.", "ragda", True, 100),
        ("Samosa Kachori Mix", "One samosa and one kachori with chutneys.", "kachori", True, 90),
        ("Chaat Corn", "Sweet corn chaat with chaat masala and lime.", "crispy-corn", True, 110),
        ("Fruit Chaat", "Seasonal fruit with chaat masala and lemon.", "salad-fruit", True, 120),
        ("Dahi Bhalla", "Soft bhalla in curd with red and green chutney.", "dahi-vada", True, 110),
        ("Aloo Tikki (3)", "Three griddled potato tikkis with chutney.", "tikki", True, 90),
        ("Poha Chivda", "Dry poha mix with peanuts and curry leaf.", "namkeen", True, 60),
        ("Sev Murmura", "Murmura tossed with sev, onion and chutney.", "bhel-puri", True, 70),
        ("Panipuri Kit", "DIY puris, flavoured water and filling at home.", "pani-puri", True, 150),
        ("Chaat Toast", "Toast topped with potato, chutneys and sev.", "toast-sandwich", True, 100),
        ("Katori Chaat", "Edible pastry cup filled with chaat.", "chaat-mix", True, 140),
        ("Aloo Chop", "Bengali spiced potato croquettes with chutney.", "cutlet-veg", True, 90),
        ("Vegetable Chop", "Bengali vegetable croquettes, fried crisp.", "cutlet-veg", True, 100),
    ]
)

_SWEETS: tuple[ExplicitItem, ...] = tuple(
    # Pool literals are written in rupees for readability; the schema stores
    # minor units (paise), so convert once here.
    ExplicitItem(n, d, f, v, p * 100)
    for n, d, f, v, p in [
        ("Gulab Jamun (2)", "Khoya dumplings soaked in cardamom rose syrup.", "gulab-jamun", True, 70),
        ("Rasgulla (2)", "Bengali chhena balls in light sugar syrup.", "rasgulla", True, 70),
        ("Sandesh", "Fresh chhena sweetened and pressed into a mould.", "sandesh", True, 90),
        ("Mishti Doi", "Bengali caramelised baked curd, set overnight.", "mishti-doi", True, 90),
        ("Rabri Malpua", "Malpua served in thickened saffron rabri.", "malpua", True, 140),
        ("Jalebi", "Fermented batter fried and dropped straight into syrup.", "jalebi", True, 80),
        ("Imarti", "Urad dal spirals, fried crisp and syrup-soaked.", "jalebi", True, 90),
        ("Kheer", "Slow-cooked rice pudding with cardamom and nuts.", "kheer", True, 90),
        ("Phirni", "Ground rice pudding set in an earthen pot.", "kheer", True, 100),
        ("Seviyan Kheer", "Vermicelli pudding with milk and saffron.", "kheer", True, 100),
        ("Gajar Halwa", "Carrot pudding slow-cooked in milk and ghee.", "gajar-halwa", True, 120),
        ("Moong Dal Halwa", "Yellow lentil halwa with dry fruits.", "halwa", True, 140),
        ("Sooji Halwa", "Semolina halwa with ghee, raisin and cashew.", "halwa", True, 90),
        ("Badam Halwa", "Almond halwa, rich and grainy.", "halwa", True, 160),
        ("Kaju Katli", "Cashew fudge cut into diamonds.", "kaju-katli", True, 200),
        ("Pista Barfi", "Pistachio fudge with a silver leaf finish.", "barfi", True, 190),
        ("Motichoor Ladoo", "Boondi ladoos bound with ghee and cardamom.", "laddu", True, 120),
        ("Besan Ladoo", "Roasted gram-flour ladoos.", "laddu", True, 110),
        ("Coconut Ladoo", "Desiccated coconut ladoos with condensed milk.", "laddu", True, 100),
        ("Milk Peda", "Khoya pedas with cardamom.", "peda", True, 130),
        ("Mathura Peda", "Brown khoya pedas from Mathura.", "mathura-pede", True, 150),
        ("Sohan Papdi", "Flaky, melt-in-mouth gram-flour sweet.", "sohan-papdi", True, 120),
        ("Balushahi", "Deep-fried flaky sweet soaked in syrup.", "barfi", True, 110),
        ("Ghevar", "Rajasthani disc sweet soaked in syrup, topped with rabri.", "ghevar", True, 160),
        ("Mysore Pak", "Ghee-heavy gram-flour sweet.", "barfi", True, 140),
        ("Double Ka Meetha", "Hyderabadi bread pudding with saffron milk.", "double-ka-meetha", True, 130),
        ("Qubani Ka Meetha", "Hyderabadi dried-apricot dessert with cream.", "qubani", True, 140),
        ("Shrikhand", "Strained sweetened curd with saffron and cardamom.", "shrikhand", True, 110),
        ("Basundi", "Thickened sweetened milk with pistachio.", "rabri", True, 130),
        ("Rabri", "Slow-reduced milk with saffron and nuts.", "rabri", True, 140),
        ("Payasam", "Kerala milk pudding with jaggery and cashew.", "payasam", True, 110),
        ("Ada Pradhaman", "Kerala payasam with rice flakes and jaggery.", "payasam-dessert", True, 130),
        ("Puran Poli", "Sweet stuffed flatbread with ghee.", "paratha", True, 110),
        ("Obbattu", "Karnataka sweet flatbread with chana dal filling.", "paratha", True, 120),
        ("Modak (3)", "Steamed rice-flour dumplings with coconut jaggery.", "modak", True, 120),
        ("Coconut Burfi", "Coconut fudge with cardamom.", "barfi", True, 110),
        ("Dates & Nuts Roll", "Date roll stuffed with roasted nuts.", "date-roll", True, 140),
        ("Anjeer Barfi", "Fig and nut fudge.", "barfi", True, 180),
        ("Dry Fruit Chikki", "Peanut and jaggery chikki bar.", "chikki", True, 70),
        ("Til Chikki", "Sesame and jaggery chikki.", "chikki", True, 60),
        ("Coconut Chikki", "Copra and jaggery chikki.", "chikki", True, 60),
        ("Bengali Sandesh (2)", "Two pieces of nolen gur sandesh.", "sandesh", True, 130),
        ("Langcha", "Bengali khoya sweet, deep fried and syrup-soaked.", "gulab-jamun", True, 110),
        ("Ledikeni", "Bengali cylindrical chhena sweet in light syrup.", "gulab-jamun", True, 120),
        ("Kheer Kadam", "Rasgulla wrapped in khoya.", "rasgulla", True, 130),
        ("Cham Cham", "Bengali chhena sweet with coconut coating.", "rasgulla", True, 110),
        ("Rajbhog", "Saffron-stuffed chhena sweet.", "bengali-sweet", True, 140),
        ("Gulab Jamun (4)", "Four pieces for sharing.", "gulab-jamun", True, 130),
        ("Assorted Mithai Box", "A half-kilo box of assorted sweets.", "sweet-platter", True, 450),
        ("Mithai Platter", "Six kinds of mithai on one plate.", "sweet-platter", True, 320),
        ("Rabri Kulfi", "Kulfi set in thickened rabri.", "kulfi", True, 140),
        ("Malpua (2)", "Two malpuas with sugar syrup.", "malpua", True, 120),
    ]
)

_ICECREAM: tuple[ExplicitItem, ...] = tuple(
    # Pool literals are written in rupees for readability; the schema stores
    # minor units (paise), so convert once here.
    ExplicitItem(n, d, f, v, p * 100)
    for n, d, f, v, p in [
        ("Vanilla Scoop", "Classic Madagascar vanilla.", "icecream-scoop", True, 70),
        ("Chocolate Scoop", "Dark cocoa ice cream.", "icecream-scoop", True, 80),
        ("Strawberry Scoop", "Real strawberry, no artificial colour.", "icecream-scoop", True, 80),
        ("Butterscotch Scoop", "Butterscotch with praline bits.", "icecream-scoop", True, 85),
        ("Kesar Pista Scoop", "Saffron and pistachio.", "icecream-scoop", True, 95),
        ("Alphonso Mango", "Made with Alphonso pulp in season.", "icecream-scoop", True, 95),
        ("Cookies & Cream", "Vanilla loaded with cookie crumble.", "icecream-scoop", True, 95),
        ("Belgian Chocolate", "Single-origin Belgian dark chocolate.", "icecream-scoop", True, 110),
        ("Coffee Swirl", "Coffee ice cream with a fudge swirl.", "icecream-scoop", True, 95),
        ("Pistachio", "Real pistachio, lightly salted.", "icecream-scoop", True, 110),
        ("Roasted Almond", "Almond-studded vanilla.", "icecream-scoop", True, 105),
        ("Mango Sorbet", "Dairy-free Alphonso sorbet.", "sorbet", True, 90),
        ("Lemon Sorbet", "Sharp, cleansing lemon sorbet.", "sorbet", True, 85),
        ("Orange Sorbet", "Fresh orange sorbet.", "sorbet", True, 85),
        ("Strawberry Sorbet", "Dairy-free strawberry.", "sorbet", True, 90),
        ("Falooda", "Vermicelli, basil seeds, rose syrup and ice cream.", "falooda", True, 130),
        ("Royal Falooda", "Falooda loaded with dry fruits and rabri.", "falooda", True, 180),
        ("Kulfi (Malai)", "Slow-churned malai kulfi on a stick.", "kulfi", True, 90),
        ("Kulfi (Pista)", "Pistachio kulfi with silver leaf.", "kulfi", True, 100),
        ("Rabri Kulfi", "Kulfi set in thickened rabri.", "kulfi", True, 120),
        ("Matka Kulfi", "Kulfi set and served in an earthen pot.", "kulfi", True, 130),
        ("Ice Cream Sandwich", "Ice cream pressed between two cookies.", "icecream-cone", True, 130),
        ("Waffle Cone", "Two scoops in a fresh waffle cone.", "waffle", True, 130),
        ("Chocolate Waffle", "Warm waffle with chocolate sauce and ice cream.", "waffle", True, 175),
        ("Belgian Waffle", "Crisp Belgian waffle with berries.", "waffle", True, 185),
        ("Pancake Stack", "Three pancakes with maple syrup and butter.", "pancake", True, 165),
        ("Blueberry Pancakes", "Pancakes with blueberry compote.", "pancake", True, 185),
        ("Choco Brownie Sundae", "Warm brownie, ice cream and fudge sauce.", "sundae", True, 195),
        ("Classic Sundae", "Two scoops with sauce, cream and a cherry.", "sundae", True, 165),
        ("Fruit Sundae", "Seasonal fruit with vanilla and honey.", "parfait", True, 175),
        ("Banana Split", "Three scoops, banana and three sauces.", "sundae", True, 210),
        ("Hot Fudge Sundae", "Warm chocolate fudge over cold ice cream.", "sundae", True, 185),
        ("Affogato", "Vanilla drowned in a fresh espresso.", "gelato", True, 140),
        ("Gelato (2 scoops)", "Italian-style dense gelato.", "gelato", True, 150),
        ("Sorbetto Trio", "Three sorbets served together.", "sorbet", True, 175),
        ("Ice Cream Stick", "Individually wrapped stick.", "stick-icecream", True, 60),
        ("Chocobar", "Vanilla bar dipped in chocolate.", "stick-icecream", True, 70),
        ("Cornetto Cone", "Rolled cone with a chocolate tip.", "icecream-cone", True, 70),
        ("Sundae Cup", "Scoop in a cup with sauce.", "sundae", True, 110),
        ("Family Ice Cream Tub", "One-litre tub to take home.", "icecream-tub", True, 380),
        ("Half Litre Tub", "Five-hundred-ml takeaway tub.", "icecream-tub", True, 220),
        ("Brownie à la Mode", "Warm brownie with two scoops.", "brownie", True, 210),
        ("Choco Lava & Ice Cream", "Molten lava cake with a scoop.", "lava-cake", True, 210),
        ("Tiramisu", "Espresso-soaked sponge with mascarpone.", "tiramisu", True, 220),
        ("Classic Cheesecake", "New York-style baked cheesecake.", "cheesecake", True, 230),
        ("Blueberry Cheesecake", "Cheesecake with blueberry compote.", "cheesecake", True, 250),
        ("Chocolate Mousse", "Dark chocolate mousse with cream.", "mousse", True, 160),
        ("Caramel Custard", "Baked custard with caramel.", "pudding", True, 140),
        ("Bread & Butter Pudding", "Warm pudding with raisins and custard.", "pudding", True, 150),
        ("Fruit Trifle", "Sponge, custard, cream and fruit.", "pudding", True, 170),
        ("Chocolate Chip Cookie", "Soft-centre cookie, baked in-house.", "cookie", True, 80),
        ("Oatmeal Raisin Cookie", "Chewy oatmeal cookie.", "cookie", True, 80),
        ("Red Velvet Pastry", "Red velvet with cream cheese frosting.", "pastry", True, 130),
        ("Black Forest Pastry", "Chocolate sponge with cherries and cream.", "cake-slice", True, 140),
        ("Butterscotch Pastry", "Butterscotch cream with praline.", "cake-slice", True, 130),
        ("Chocolate Truffle Pastry", "Dark chocolate truffle slice.", "cake-slice", True, 150),
        ("Vanilla Pastry", "Vanilla sponge with fresh cream.", "cake-slice", True, 120),
        ("Fruit Pastry", "Vanilla sponge topped with fresh fruit.", "cake-fruit", True, 150),
        ("Tiramisu Cup", "Individual tiramisu portion.", "tiramisu", True, 180),
        ("Mango Cheesecake", "Mango topping on a set cheesecake.", "cheesecake", True, 240),
        ("Lotus Biscoff Cheesecake", "Biscoff cheesecake with crumb base.", "cheesecake", True, 260),
    ]
)

_BAKERY: tuple[ExplicitItem, ...] = tuple(
    # Pool literals are written in rupees for readability; the schema stores
    # minor units (paise), so convert once here.
    ExplicitItem(n, d, f, v, p * 100)
    for n, d, f, v, p in [
        ("Butter Croissant", "Laminated over three days, baked each morning.", "croissant", True, 90),
        ("Almond Croissant", "Croissant filled and topped with frangipane.", "croissant", True, 130),
        ("Chocolate Croissant", "Pain au chocolat with two batons.", "croissant", True, 120),
        ("Pain au Raisin", "Crème pâtissière and raisins in a spiral.", "pastry", True, 120),
        ("Sourdough Loaf", "Naturally leavened, 36-hour ferment.", "bread-whole", True, 180),
        ("Multigrain Loaf", "Seeded whole-grain sandwich loaf.", "bread-loaf", True, 160),
        ("Milk Bread", "Soft Japanese-style milk bread loaf.", "bread-loaf", True, 140),
        ("Focaccia", "Olive oil focaccia with rosemary and sea salt.", "focaccia", True, 150),
        ("Garlic Focaccia", "Focaccia loaded with roasted garlic.", "focaccia", True, 170),
        ("Ciabatta", "Open-crumb Italian slipper bread.", "bread-whole", True, 150),
        ("Baguette", "Crackling crust, soft crumb.", "bread-whole", True, 130),
        ("Dinner Rolls (6)", "Six soft buttered rolls.", "bread-bun", True, 110),
        ("Burger Buns (4)", "Four sesame-topped buns.", "bread-bun", True, 100),
        ("Hot Dog Buns (4)", "Four split-top buns.", "bread-bun", True, 100),
        ("Cinnamon Roll", "Swirled with cinnamon and cream cheese glaze.", "pastry", True, 140),
        ("Danish Pastry", "Fruit-topped laminated pastry.", "pastry", True, 130),
        ("Eclair", "Choux filled with vanilla crème pâtissière.", "eclair", True, 120),
        ("Chocolate Eclair", "Eclair glazed with dark chocolate.", "eclair", True, 140),
        ("Profiteroles (3)", "Choux puffs filled and drizzled with chocolate.", "pastry", True, 160),
        ("Macaron (4)", "Four almond macarons, assorted flavours.", "macaron", True, 200),
        ("Tart Shell (6)", "Six crisp tart shells for home.", "tart", True, 120),
        ("Fruit Tart", "Custard tart topped with glazed fruit.", "tart", True, 190),
        ("Lemon Tart", "Sharp lemon curd in a butter shell.", "tart", True, 170),
        ("Chocolate Tart", "Dark chocolate ganache in a cocoa shell.", "tart", True, 190),
        ("Banana Bread", "Moist banana loaf with walnuts.", "bread-loaf", True, 120),
        ("Carrot Cake Slice", "Spiced carrot cake with cream cheese.", "cake-slice", True, 160),
        ("Plum Cake", "Festive fruit cake soaked in juice.", "cake-fruit", True, 150),
        ("Brownie (Slice)", "Fudgy dark chocolate brownie.", "brownie", True, 130),
        ("Blondie", "White chocolate and walnut blondie.", "brownie", True, 130),
        ("Chocolate Chip Cookie (3)", "Three soft-baked cookies.", "cookie", True, 150),
        ("Atta Biscuit", "Whole-wheat nankhatai-style biscuit.", "biscuit", True, 80),
        ("Nankhatai", "Ghee shortbread with cardamom.", "biscuit", True, 90),
        ("Rusk (Pack)", "Eggless tea rusk, 250 g pack.", "biscuit", True, 110),
        ("Garlic Bread Loaf", "Sliced loaf with garlic butter.", "bread-garlic", True, 160),
        ("Bread Sticks (Pack)", "Crunchy breadsticks, 200 g.", "bread-sticks", True, 100),
        ("Pita (4)", "Four pocket pita breads.", "pita", True, 130),
        ("Tortilla (6)", "Six flour tortillas.", "bread-whole", True, 140),
        ("Burger Sliders (6)", "Six mini buns for sliders.", "bread-bun", True, 150),
        ("Brioche Buns (4)", "Rich, buttery brioche buns.", "bread-bun", True, 180),
        ("Focaccia Sliders", "Focaccia cut for sliders.", "focaccia", True, 170),
        ("Sourdough Slices (8)", "Pre-sliced sourdough loaf.", "bread-loaf", True, 190),
        ("Multigrain Slices (8)", "Pre-sliced multigrain loaf.", "bread-loaf", True, 170),
        ("Bread (Whole Loaf)", "Classic white sandwich loaf.", "bread-loaf", True, 90),
        ("Burger Buns (8)", "Eight sesame buns.", "bread-bun", True, 170),
        ("Hot Cross Buns (6)", "Spiced fruit buns.", "bread-bun", True, 190),
        ("Focaccia Slab", "Half-tray focaccia for sharing.", "focaccia", True, 320),
        ("Baguette (Large)", "A full-size baguette.", "bread-whole", True, 180),
        ("Cinnamon Sugar Donut", "Fried donut rolled in cinnamon sugar.", "donut", True, 100),
        ("Glazed Donut", "Classic glazed ring donut.", "donut", True, 90),
        ("Chocolate Donut", "Chocolate-iced donut with sprinkles.", "donut", True, 110),
        ("Boston Cream Donut", "Custard-filled, chocolate-topped.", "donut", True, 130),
        ("Donut Box (6)", "Six assorted donuts.", "donut", True, 480),
    ]
)

_BAKERY = tuple(_BAKERY)


# ---------------------------------------------------------------------------
# recipes
# ---------------------------------------------------------------------------

RECIPES: dict[str, Recipe] = {}


def _add(recipe: Recipe) -> None:
    RECIPES[recipe.key] = recipe


_add(
    Recipe(
        key="veg_starters_tandoor",
        title="Veg Starters",
        tags=("indian", "north-indian", "snacks", "vegetarian"),
        groups=(_g(_VEG_STARTER_BASES, ("tikka", "kebab", "chaap", "fry", "cutlet", "tikki")),),
        price_min=14900,
        price_max=29900,
    )
)
_add(
    Recipe(
        key="veg_starters_wok",
        title="Veg Starters",
        tags=("chinese", "indo-chinese", "snacks", "vegetarian"),
        groups=(
            _g(
                ("paneer", "mushroom", "babycorn", "sweetcorn", "gobi", "vegmix", "corn", "broccoli"),
                ("chilli", "manchurian", "crispy", "salt-pepper", "65", "schezwan"),
            ),
        ),
        price_min=15900,
        price_max=27900,
    )
)
_add(
    Recipe(
        key="nonveg_starters_tandoor",
        title="Non-Veg Starters",
        tags=("indian", "north-indian", "kebabs", "non-vegetarian"),
        groups=(_g(_NONVEG_STARTER_BASES, ("tikka", "kebab", "chaap", "fry", "cutlet", "65", "koliwada", "grill")),),
        price_min=21900,
        price_max=39900,
    )
)
_add(
    Recipe(
        key="nonveg_starters_wok",
        title="Non-Veg Starters",
        tags=("chinese", "indo-chinese", "non-vegetarian"),
        groups=(
            _g(
                ("chicken", "prawn", "fish", "egg", "keema", "crab"),
                ("chilli", "manchurian", "crispy", "salt-pepper", "65", "koliwada", "fry", "schezwan"),
            ),
        ),
        price_min=22900,
        price_max=38900,
    )
)
_add(
    Recipe(
        key="veg_curry",
        title="Main Course",
        tags=("indian", "vegetarian"),
        groups=(
            _g(
                ("paneer", "mushroom", "palak", "vegmix", "soya", "corn", "aloo", "chana", "rajma", "dal"),
                ("butter-masala", "kadai", "masala", "do-pyaza", "handi", "saag", "lababdar", "home-style"),
            ),
        ),
        price_min=17900,
        price_max=32900,
    )
)
_add(
    Recipe(
        key="veg_dry_sabzi",
        title="Dry Sabzi",
        tags=("indian", "vegetarian"),
        groups=(
            _g(
                ("aloo", "gobi", "vegmix", "paneer", "mushroom", "babycorn", "palak", "corn", "broccoli", "sweetcorn"),
                ("tawa", "masala", "kadai", "do-pyaza", "handi", "fry"),
            ),
        ),
        price_min=15900,
        price_max=27900,
    )
)
_add(
    Recipe(
        key="nonveg_curry",
        title="Main Course",
        tags=("indian", "non-vegetarian"),
        groups=(
            _g(
                ("chicken", "mutton", "fish", "prawn", "egg", "crab"),
                (
                    "masala",
                    "kadai",
                    "curry",
                    "gravy",
                    "do-pyaza",
                    "handi",
                    "korma",
                    "chettinad",
                    "vindaloo",
                    "rogan-josh",
                    "butter-gravy",
                    "lababdar",
                ),
            ),
        ),
        price_min=24900,
        price_max=44900,
    )
)
_add(
    Recipe(
        key="biryani",
        title="Biryani & Rice",
        tags=("biryani", "indian"),
        groups=(
            _g(
                ("by-chicken", "by-mutton", "by-egg", "by-prawn", "by-paneer", "by-veg", "by-mushroom", "by-fish", "by-keema", "by-crab", "by-soya", "by-corn"),
                ("dum-biryani", "handi-biryani", "fry-biryani", "family-biryani", "kacchi-biryani", "pulao-side"),
            ),
        ),
        price_min=18900,
        price_max=49900,
    )
)
_add(
    Recipe(
        key="breads",
        title="Breads & Rice",
        tags=("indian", "north-indian", "vegetarian"),
        explicit=_BREADS,
    )
)
_add(
    Recipe(
        key="soups",
        title="Soups",
        tags=(),
        explicit=_SOUPS,
    )
)
_add(
    Recipe(
        key="chaat",
        title="Chaat & Street Food",
        tags=("street-food", "snacks", "vegetarian"),
        explicit=_CHAAT,
    )
)
_add(
    Recipe(
        key="sweets",
        title="Desserts",
        tags=("desserts", "vegetarian"),
        explicit=_SWEETS,
    )
)
_add(
    Recipe(
        key="icecream",
        title="Ice Cream & Desserts",
        tags=("ice-cream", "desserts", "vegetarian"),
        explicit=_ICECREAM,
    )
)
_add(
    Recipe(
        key="bakery",
        title="Bakery",
        tags=("cakes-bakery", "vegetarian"),
        explicit=_BAKERY,
    )
)
_add(
    Recipe(
        key="pizza_classic",
        title="Classic Pizzas",
        tags=("pizza", "vegetarian"),
        groups=(
            _g(
                ("pz-margherita", "pz-farmhouse", "pz-paneer", "pz-four-cheese", "pz-mexican", "pz-corn", "pz-mushroom", "pz-supreme", "pz-spicy-paneer", "pz-tomato", "pz-bbq", "pz-tandoori", "pz-pepperoni", "pz-sausage", "pz-kebab", "pz-egg"),
                ("classic-pizza", "thin-crust", "pan-pizza", "cheese-burst", "wheat-crust", "stuffed-crust"),
            ),
        ),
        price_min=22900,
        price_max=59900,
    )
)
_add(
    Recipe(
        key="pasta",
        title="Pasta",
        tags=("pasta", "italian", "vegetarian"),
        groups=(
            _g(
                ("pd-penne", "pd-spaghetti", "pd-fusilli", "pd-farfalle", "pd-rigatoni", "pd-macaroni", "pd-fettuccine", "pd-lasagne", "pd-chicken"),
                ("alfredo", "arrabiata", "pesto", "marinara", "aglio-olio", "white-sauce", "red-sauce", "baked-pasta", "pink-sauce"),
            ),
        ),
        price_min=24900,
        price_max=44900,
    )
)
_add(
    Recipe(
        key="burgers",
        title="Burgers",
        tags=("burgers", "snacks", "vegetarian"),
        groups=(
            _g(
                ("bg-veg", "bg-aloo", "bg-paneer", "bg-cheese", "bg-crispy", "bg-corn", "bg-mushroom", "bg-chicken", "bg-grilled", "bg-egg", "bg-mutton"),
                ("burger", "cheese-burger", "double-burger", "zinger-burger", "grilled-burger", "jumbo-burger"),
            ),
        ),
        price_min=9900,
        price_max=25900,
    )
)
_add(
    Recipe(
        key="sandwiches",
        title="Sandwiches",
        tags=("sandwiches", "snacks", "vegetarian"),
        groups=(
            _g(
                ("sw-veg", "sw-cheese", "sw-grilled-veg", "sw-paneer", "sw-corn", "sw-tandoori", "sw-mayo", "sw-chicken", "sw-egg", "sw-tuna"),
                ("sandwich", "club-sandwich", "panini-press", "toasted", "sub-roll"),
            ),
        ),
        price_min=8900,
        price_max=21900,
    )
)
_add(
    Recipe(
        key="wraps",
        title="Wraps & Rolls",
        tags=("wraps-rolls", "street-food", "vegetarian"),
        groups=(
            _g(
                ("wr-veg", "wr-paneer", "wr-aloo", "wr-soya", "wr-mushroom", "wr-cheese", "wr-chicken", "wr-egg", "wr-keema", "wr-fish"),
                ("kathi-roll", "paratha-roll", "frankie-roll", "wrap-foil", "shawarma-wrap"),
            ),
        ),
        price_min=10900,
        price_max=24900,
    )
)
_add(
    Recipe(
        key="noodles",
        title="Noodles",
        tags=("noodles", "chinese", "indo-chinese", "vegetarian"),
        groups=(
            _g(
                ("nl-veg", "nl-egg", "nl-chicken", "nl-paneer", "nl-prawn", "nl-mushroom", "nl-mixed", "nl-tofu"),
                ("hakka-noodles", "schezwan-noodles", "chilli-garlic-noodles", "butter-noodles", "singapore-noodles", "chowmein-noodles", "noodle-soup"),
            ),
        ),
        price_min=15900,
        price_max=28900,
    )
)
_add(
    Recipe(
        key="fried_rice",
        title="Fried Rice",
        tags=("chinese", "indo-chinese", "vegetarian"),
        groups=(
            _g(
                ("fr-veg", "fr-egg", "fr-chicken", "fr-prawn", "fr-paneer", "fr-mushroom", "fr-schezwan", "fr-burnt-garlic"),
                ("fried-rice", "garlic-rice", "burnt-garlic-rice", "singapore-rice", "jeera-rice-side"),
            ),
        ),
        price_min=15900,
        price_max=27900,
    )
)
_add(
    Recipe(
        key="chinese_mains",
        title="Main Course",
        tags=("chinese", "indo-chinese", "vegetarian"),
        groups=(
            _g(
                ("cm-paneer", "cm-veg", "cm-mushroom", "cm-corn", "cm-chicken", "cm-mutton", "cm-fish", "cm-prawn", "cm-egg"),
                ("sweet-sour", "kungpao", "manchurian", "chilli", "crispy", "salt-pepper", "schezwan", "gravy"),
            ),
        ),
        price_min=21900,
        price_max=38900,
    )
)
_add(
    Recipe(
        key="momos",
        title="Momos",
        tags=("momos", "snacks", "vegetarian"),
        groups=(
            _g(
                ("mo-veg", "mo-paneer", "mo-cheese", "mo-corn", "mo-mushroom", "mo-chicken", "mo-egg", "mo-prawn"),
                ("momo-steamed", "momo-fried", "momo-chilli", "momo-tandoori", "momo-panfried", "momo-kurkure", "momo-cheese"),
            ),
        ),
        price_min=9900,
        price_max=22900,
    )
)
_add(
    Recipe(
        key="salads",
        title="Salads",
        tags=("salads", "healthy-food", "vegetarian"),
        groups=(
            _g(
                ("sl-green", "sl-caesar", "sl-greek", "sl-quinoa", "sl-pasta", "sl-fruit", "sl-chickpea", "sl-sprouts", "sl-chicken", "sl-egg", "sl-fish", "sl-prawn"),
                (
                    "salad-bowl",
                    "salad-classic",
                    "salad-garden",
                    "salad-cobb",
                    "salad-waldorf",
                    "salad-tabouli",
                    "salad-fattoush",
                    "salad-russian",
                    "salad-coleslaw",
                    "salad-beetroot",
                    "salad-cucumber",
                    "salad-thai",
                    "salad-mediterranean",
                    "salad-kachumber",
                    "salad-onion",
                    "salad-mix-fruit",
                ),
            ),
        ),
        price_min=13900,
        price_max=29900,
    )
)
_add(
    Recipe(
        key="bowls",
        title="Bowls & Grills",
        tags=("healthy-food", "salads", "vegetarian"),
        groups=(
            _g(
                ("bw-quinoa", "bw-oats", "bw-avocado", "bw-veg", "bw-chickpea", "bw-broccoli", "bw-chicken", "bw-fish", "bw-egg", "bw-paneer"),
                (
                    "grain-bowl",
                    "protein-bowl",
                    "salad-bowl",
                    "bowl-poke",
                    "bowl-buddha",
                    "bowl-hummus",
                    "bowl-falafel",
                    "bowl-cauliflower",
                    "bowl-sweetpotato",
                    "bowl-miso",
                    "bowl-soba",
                    "bowl-taco",
                    "bowl-ricotta",
                ),
            ),
        ),
        price_min=18900,
        price_max=34900,
    )
)
_add(
    Recipe(
        key="south_breakfast",
        title="Dosa & Idli",
        tags=("south-indian", "vegetarian", "street-food"),
        groups=(
            _g(
                ("so-plain", "so-masala", "so-onion", "so-paneer", "so-cheese", "so-rava", "so-mysore", "so-schezwan", "so-podi", "so-ghee", "so-karam", "so-butter", "so-garlic", "so-corn", "so-mixed", "so-chicken", "so-egg", "so-mushroom", "so-babycorn", "so-beetroot"),
                ("dosa", "masala-dosa", "uttapam", "set-dosa", "pesarattu", "appam", "idiyappam"),
            ),
        ),
        price_min=6900,
        price_max=18900,
    )
)
_add(
    Recipe(
        key="south_thali",
        title="Meals & Thali",
        tags=("south-indian", "thalis", "vegetarian"),
        groups=(
            _g(
                ("so-plain", "so-masala", "so-onion", "so-paneer", "so-mixed", "so-mushroom", "so-chicken", "so-egg", "so-babycorn", "so-corn"),
                ("idli-plate", "vada-plate", "pongal-plate", "puri-plate", "thali-south", "filter-coffee", "kesari-bath", "khara-bath", "vada-sambar", "idli-fry", "rava-dosa", "ghee-roast", "paper-dosa", "mysore-masala", "kerala-parotta", "appam-stew", "puttu", "avial", "rasam-plate", "sambar-plate", "payasam-plate", "curd-rice-plate", "lemon-rice", "tamarind-rice", "coconut-rice"),
            ),
        ),
        price_min=4900,
        price_max=21900,
    )
)
_add(
    Recipe(
        key="north_gravy",
        title="Main Course",
        tags=("indian", "north-indian"),
        groups=(
            _g(
                ("paneer", "mushroom", "palak", "vegmix", "soya", "corn", "chicken", "mutton", "fish", "prawn", "egg"),
                (
                    "home-style",
                    "dhaba-style",
                    "butter-gravy",
                    "lababdar",
                    "jalfrezi",
                    "makhani",
                    "korma-creamy",
                    "nihari",
                    "paya",
                    "stew-kerala",
                    "moilee",
                    "kalia",
                    "shorshe",
                    "kosha",
                    "dal-tadka",
                    "dal-fry",
                    "chole-masala",
                    "rajma-masala",
                    "pindi-chole",
                ),
            ),
        ),
        price_min=19900,
        price_max=42900,
    )
)
_add(
    Recipe(
        key="veg_classics",
        title="Veg Main Course",
        tags=("indian", "vegetarian"),
        groups=(
            _g(
                ("aloo", "gobi", "paneer", "palak", "vegmix", "mushroom", "soya", "chana", "rajma", "dal"),
                (
                    "aloo-gobi",
                    "bhindi-masala",
                    "palak-paneer",
                    "sarson-ka-saag",
                    "malai-kofta",
                    "paneer-butter-masala",
                    "kadai-paneer",
                    "shahi-paneer",
                    "matar-paneer",
                    "paneer-tikka-masala",
                    "mushroom-masala",
                    "veg-kadai",
                    "mix-veg",
                    "soya-masala",
                    "egg-curry",
                    "egg-bhurji",
                    "anda-curry",
                    "dal-tadka",
                    "dal-fry",
                    "chole-masala",
                    "rajma-masala",
                    "pindi-chole",
                    "home-style",
                    "dhaba-style",
                    "jalfrezi",
                    "korma-creamy",
                    "lababdar",
                    "kalia",
                ),
            ),
        ),
        price_min=17900,
        price_max=32900,
    )
)
_add(
    Recipe(
        key="nonveg_classics",
        title="Non-Veg Main Course",
        tags=("indian", "non-vegetarian"),
        groups=(
            _g(
                ("chicken", "mutton", "fish", "prawn", "egg", "crab"),
                (
                    "chicken-curry",
                    "chicken-handi",
                    "butter-chicken",
                    "chicken-tikka-masala",
                    "chicken-kadai",
                    "chicken-lababdar",
                    "chicken-korma",
                    "chicken-chettinad",
                    "chicken-vindaloo",
                    "chicken-kosha",
                    "mutton-rogan-josh",
                    "mutton-curry",
                    "mutton-kadai",
                    "mutton-korma",
                    "mutton-kosha",
                    "mutton-nihari",
                    "fish-curry",
                    "fish-moilee",
                    "fish-shorshe",
                    "prawn-curry",
                    "prawn-masala",
                    "prawn-ghee-roast",
                    "crab-masala",
                    "egg-curry",
                    "egg-bhurji",
                    "anda-curry",
                    "nihari",
                    "paya",
                ),
            ),
        ),
        price_min=24900,
        price_max=52900,
    )
)
_add(
    Recipe(
        key="tandoor",
        title="Tandoor & Kebabs",
        tags=("indian", "north-indian", "kebabs", "non-vegetarian"),
        groups=(
            _g(
                ("tn-chicken", "tn-mutton", "tn-fish", "tn-prawn", "tn-paneer", "tn-mushroom", "tn-babycorn", "tn-veg", "tn-keema", "tn-egg"),
                ("tandoori", "seekh", "galouti", "shami", "tikka-platter", "kebab-platter", "kakori", "reshmi", "malai-tikka", "afghani", "fish-tandoori", "prawn-tandoori", "paneer-tandoori", "half-tandoori"),
            ),
        ),
        price_min=24900,
        price_max=59900,
    )
)
_add(
    Recipe(
        key="kebab_grill",
        title="Kebabs & Grills",
        tags=("kebabs", "indian", "north-indian", "non-vegetarian"),
        groups=(
            _g(
                ("kb-chicken", "kb-mutton", "kb-keema", "kb-paneer", "kb-veg", "kb-fish", "kb-prawn", "kb-egg", "kb-mushroom"),
                ("seekh", "galouti", "shami", "tikka-platter", "kebab-platter", "kakori", "reshmi", "malai-tikka", "afghani", "fish-tandoori", "prawn-tandoori", "paneer-tandoori", "tandoori", "half-tandoori"),
            ),
        ),
        price_min=26900,
        price_max=64900,
    )
)
_add(
    Recipe(
        key="thali",
        title="Thalis & Combos",
        tags=("thalis", "indian", "vegetarian"),
        groups=(
            _g(
                ("so-plain", "so-masala", "so-mixed", "so-chicken", "so-egg", "paneer", "chicken", "vegmix", "mushroom", "egg"),
                ("meals-south", "meals-north", "meals-gujarati", "meals-rajasthani", "meals-maharashtrian", "meals-bengali", "meals-eggetarian", "meals-nonveg", "meals-mini"),
            ),
        ),
        price_min=14900,
        price_max=44900,
    )
)


# ---------------------------------------------------------------------------
# beverages
# ---------------------------------------------------------------------------


def _pool(
    base_ids: tuple[str, ...],
    finish: str,
    price_min: int,
    price_max: int,
) -> tuple[ExplicitItem, ...]:
    """Build an explicit pool from finished dish names in ``_BASES``.

    Used where a hand-written *label* is already the full dish name (``Espresso``,
    ``Sweet Lassi``). The description is composed from the base's clause plus a
    shared finishing phrase, so every item reads naturally and stays distinct.
    """
    out: list[ExplicitItem] = []
    seen: set[str] = set()
    for base_id in base_ids:
        label, veg, food, clause = _BASES[base_id]
        if label in seen:
            raise ValueError(f"duplicate label {label!r} in pool")
        seen.add(label)
        out.append(
            ExplicitItem(
                name=label,
                description=f"{clause} {finish}",
                food_type=food,
                veg=veg,
                price_minor=_price_for(label, price_min, price_max, 0),
            )
        )
    return tuple(out)


_SMOOTHIE_BASES = (
    "sm-mango", "sm-strawberry", "sm-banana", "sm-berry", "sm-blueberry",
    "sm-kiwi", "sm-pineapple", "sm-choco", "sm-coffee", "sm-green", "sm-oats",
    "sm-peanut", "sm-avocado", "sm-apple", "sm-watermelon", "sm-pomegranate",
    "sm-muskmelon", "sm-oreo", "sm-curd", "sm-dryfruits",
)

_SHAKE_BASES = (
    "sh-vanilla", "sh-chocolate", "sh-strawberry", "sh-mango", "sh-banana",
    "sh-oreo", "sh-caramel", "sh-cookies", "sh-dryfruits", "sh-roohafza",
    "sh-pista", "sh-coffee", "sh-butterscotch", "sh-walnut", "sh-kitkat",
    "sh-brownie", "sh-almond", "sh-kiwi", "sh-blackcurrant", "sh-choco-mint",
)

_JUICE_BASES = (
    "ju-orange", "ju-mango", "ju-watermelon", "ju-pomegranate", "ju-sweetlime",
    "ju-cucumber", "ju-carrot", "ju-beetroot", "ju-pineapple", "ju-apple",
    "ju-muskmelon", "ju-grape", "ju-guava", "ju-papaya", "ju-banana",
    "ju-tomato", "ju-mixed", "ju-amla", "ju-aloe", "ju-wheatgrass", "ju-ginger",
    "ju-spinach", "ju-kale", "ju-celery", "ju-coconut", "ju-blueberry",
    "ju-kiwi", "ju-strawberry", "ju-peach", "ju-pear", "ju-lychee",
    "ju-chikoo", "ju-cashew",
)

_DETOX_BASES = (
    "ju-cucumber", "ju-carrot", "ju-beetroot", "ju-spinach", "ju-kale",
    "ju-celery", "ju-wheatgrass", "ju-ginger", "ju-amla", "ju-aloe",
)

_COOLER_BASES = (
    "cl-sweet", "cl-salted", "cl-mango", "cl-rose", "cl-pineapple",
    "cl-kesar", "cl-paan", "cl-lychee", "cl-guava",
    "cl-kokum", "cl-jeera", "cl-mint", "cl-ginger", "cl-masala", "cl-plain",
    "cl-buttermilk", "cl-thandai", "cl-sattu", "cl-aam-panna", "cl-shikanji",
    "cl-jal-jeera", "cl-nariyal", "cl-lemonade", "cl-lime-soda",
    "cl-lemon-soda", "cl-masala-soda", "cl-orange-soda", "cl-blue-lagoon",
    "cl-mojito", "cl-cucumber-cooler", "cl-green-apple", "cl-peach-cooler",
    "cl-lychee-cooler", "cl-watermelon-cooler", "cl-grape-cooler",
    "cl-pineapple-cooler", "cl-muskmelon-cooler", "cl-ginger-ale",
    "cl-virgin-mule", "cl-soda-icecream", "cl-falooda-cooler", "cl-chikoo",
    "cl-cold-coffee", "cl-horchata", "cl-tender-coconut",
)

_COFFEE_BASES = (
    "cf-espresso", "cf-americano", "cf-latte", "cf-cappuccino", "cf-mocha",
    "cf-macchiato", "cf-flat-white", "cf-cortado", "cf-lungo", "cf-doppio",
    "cf-filter", "cf-instant", "cf-hazelnut", "cf-vanilla", "cf-caramel",
    "cf-cinnamon", "cf-white-chocolate", "cf-irish", "cf-affogato",
    "cf-cold-brew", "cf-iced-latte", "cf-iced-mocha", "cf-iced-cappuccino",
    "cf-frappe", "cf-caramel-frappe", "cf-mocha-frappe", "cf-vanilla-frappe",
    "cf-cookie-frappe", "cf-coconut-latte", "cf-oat-latte", "cf-almond-latte",
    "cf-soy-latte", "cf-turmeric", "cf-matcha", "cf-hot-chocolate",
    "cf-white-hot-chocolate", "cf-masala-coffee", "cf-vietnamese", "cf-nutella",
    "cf-peanut", "cf-biscoff", "cf-rose-latte", "cf-dalgona", "cf-decaf",
    "cf-con-panna",
)

_TEA_BASES = (
    "te-masala", "te-adrak", "te-elaichi", "te-kadak", "te-cutting",
    "te-tulsi", "te-sulaimani", "te-green", "te-ginger-green", "te-lemon-green",
    "te-honey-green", "te-mint", "te-chamomile", "te-hibiscus", "te-peppermint",
    "te-lavender", "te-earl-grey", "te-breakfast", "te-assam", "te-darjeeling",
    "te-nilgiri", "te-kesar", "te-pista", "te-butter", "te-kahwa",
    "te-licorice", "te-rooibos", "te-lemongrass", "te-ginger-lemon",
    "te-black-lemon", "te-honey-lemon", "te-jasmine", "te-matcha", "te-iced-tea",
    "te-iced-lemon", "te-iced-peach", "te-iced-mint", "te-iced-hibiscus",
    "te-iced-green", "te-iced-mango", "te-rose", "te-turmeric", "te-cinnamon",
    "te-spiced", "te-berry", "te-apple", "te-pineapple", "te-orange-peel",
    "te-butterfly", "te-fennel", "te-ashwagandha", "te-ginseng", "te-osmanthus",
    "te-chai-affogato", "te-thandai", "te-tulsi-turmeric", "te-pulled",
    "te-masala-iced", "te-cold-brew-green",
)

_MOCKTAIL_BASES = (
    "mk-mojito", "mk-blue-lagoon", "mk-sunset", "mk-orchard", "mk-cucumber",
    "mk-ginger-lime", "mk-watermelon", "mk-pineapple", "mk-mango", "mk-grape",
    "mk-green-apple", "mk-peach", "mk-lychee", "mk-passion", "mk-citrus",
    "mk-berry", "mk-tropical", "mk-coconut", "mk-rose", "mk-kokum",
    "mk-aam-panna", "mk-shikanji", "mk-jal-jeera", "mk-thandai", "mk-sattu",
    "mk-virgin-mule", "mk-shirley", "mk-arnold",
    "mk-italian-soda", "mk-cream-soda", "mk-orangeade", "mk-lemonade-mint",
    "mk-strawberry", "mk-muskmelon", "mk-guava", "mk-pomegranate",
    "mk-cola-float", "mk-root-beer", "mk-butterfly", "mk-citrus-mint",
    "mk-plum", "mk-apple-mint", "mk-sugarcane", "mk-carrot-ginger",
)

_add(
    Recipe(
        key="juices",
        title="Fresh Juices",
        tags=("beverages", "juices", "cold-beverages", "healthy-food", "vegetarian"),
        groups=(
            _g(_JUICE_BASES, ("juice", "fresh-juice", "juice-cooler")),
            _g(_DETOX_BASES, ("detox-juice",)),
        ),
        price_min=4000,
        price_max=17900,
    )
)
_add(
    Recipe(
        key="smoothies",
        title="Smoothies",
        tags=("beverages", "smoothies", "cold-beverages", "healthy-food", "vegetarian"),
        groups=(_g(_SMOOTHIE_BASES, ("smoothie", "smoothie-bowl", "protein-smoothie", "yoghurt-smoothie")),),
        price_min=11900,
        price_max=27900,
    )
)
_add(
    Recipe(
        key="shakes",
        title="Shakes & Thick Shakes",
        tags=("beverages", "milkshakes", "cold-beverages", "vegetarian"),
        groups=(_g(_SHAKE_BASES, ("milkshake", "thick-shake", "float", "shake-icecream")),),
        price_min=11900,
        price_max=29900,
    )
)
_add(
    Recipe(
        key="coolers",
        title="Coolers & Lassi",
        tags=("beverages", "cold-beverages", "vegetarian"),
        explicit=_pool(_COOLER_BASES, "chilled thoroughly before serving.", 5000, 24900),
    )
)
_add(
    Recipe(
        key="coffee",
        title="Coffee",
        tags=("beverages", "coffee", "hot-beverages", "cold-beverages", "vegetarian"),
        explicit=_pool(_COFFEE_BASES, "prepared fresh to order at the bar.", 7000, 34900),
    )
)
_add(
    Recipe(
        key="tea",
        title="Tea & Chai",
        tags=("beverages", "tea", "hot-beverages", "cold-beverages", "vegetarian"),
        explicit=_pool(_TEA_BASES, "steeped to order and served fresh.", 3000, 25900),
    )
)
_add(
    Recipe(
        key="mocktails",
        title="Mocktails & Coolers",
        tags=("beverages", "cold-beverages", "vegetarian"),
        explicit=_pool(_MOCKTAIL_BASES, "shaken with ice and served long.", 6000, 26900),
    )
)
