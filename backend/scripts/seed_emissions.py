"""Populate FoodEmissions and CategoryEmissions from the committed dataset.

The originals lived only in a hosted database that has since been deleted,
with no schema, no seed and no note of where the numbers came from. This
rebuilds them from Our World in Data's food emissions figures, which are
derived from Poore & Nemecek (2018). See data/SOURCE.md.

Emissions are kg CO2-equivalent per kilogram of product. The CSV gives the
supply chain broken into stages; the total is their sum, which matches OWID's
own headline figure per product.

Usage:
    DATABASE_URL=postgresql+psycopg2://... python seed_emissions.py
"""

import csv
import os
import sys
from pathlib import Path

from sqlalchemy import create_engine, text

SCHEMA = "sustainapet"
CSV_PATH = Path(__file__).parent / "data" / "food-emissions-supply-chain.csv"

# Impact is a display label the app passes through to the client. Thresholds
# are in kg CO2e per kg and chosen so the bands are legible to a user rather
# than statistically derived: plants sit low, most animal products high.
def impact_band(kg_co2e: float) -> str:
    if kg_co2e < 2:
        return "Low"
    if kg_co2e < 10:
        return "Medium"
    return "High"


# Category emissions are the mean of their members. The mapping is by hand
# because the source data has no category column, and the sentence-transformer
# index matches receipt items against these names when no direct food match is
# found.
CATEGORIES = {
    "Beef": ["Beef (beef herd)", "Beef (dairy herd)"],
    "Lamb": ["Lamb & Mutton"],
    "Pork": ["Pig Meat"],
    "Poultry": ["Poultry Meat"],
    "Seafood": ["Fish (farmed)", "Shrimps (farmed)"],
    "Dairy": ["Cheese", "Milk"],
    "Eggs": ["Eggs"],
    "Fruit": ["Apples", "Bananas", "Berries & Grapes", "Citrus Fruit", "Other Fruit"],
    "Vegetables": [
        "Brassicas", "Onions & Leeks", "Other Vegetables", "Potatoes",
        "Root Vegetables", "Tomatoes", "Cassava",
    ],
    "Grains": ["Barley", "Maize", "Oatmeal", "Rice", "Wheat & Rye"],
    "Legumes": ["Other Pulses", "Peas", "Groundnuts", "Tofu", "Soy milk"],
    "Nuts": ["Nuts"],
    "Oils": [
        "Olive Oil", "Palm Oil", "Rapeseed Oil", "Soybean Oil", "Sunflower Oil",
    ],
    "Sugar": ["Beet Sugar", "Cane Sugar"],
    "Chocolate": ["Dark Chocolate"],
    "Drinks": ["Coffee", "Wine"],
}


def load_foods():
    """Return {product name: total kg CO2e per kg} from the committed CSV."""
    foods = {}
    with CSV_PATH.open(newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            name = row["Entity"].strip()
            total = 0.0
            for column, value in row.items():
                if column in ("Entity", "Year") or value in (None, ""):
                    continue
                try:
                    total += float(value)
                except ValueError:
                    pass
            foods[name] = round(total, 4)
    return foods


def main():
    url = os.environ.get("DATABASE_URL")
    if not url:
        sys.exit("DATABASE_URL is not set")
    if not CSV_PATH.exists():
        sys.exit(f"missing dataset: {CSV_PATH}")

    foods = load_foods()
    print(f"loaded {len(foods)} food products from {CSV_PATH.name}")

    categories = {}
    for category, members in CATEGORIES.items():
        values = [foods[m] for m in members if m in foods]
        missing = [m for m in members if m not in foods]
        if missing:
            print(f"  warning: {category} references unknown products: {missing}")
        if values:
            categories[category] = round(sum(values) / len(values), 4)

    engine = create_engine(url)
    with engine.begin() as conn:
        conn.execute(text(f'TRUNCATE {SCHEMA}."FoodEmissions"'))
        conn.execute(text(f'TRUNCATE {SCHEMA}."CategoryEmissions"'))

        for name, kg in foods.items():
            conn.execute(
                text(
                    f'INSERT INTO {SCHEMA}."FoodEmissions" ("Name","Emissions","Impact") '
                    "VALUES (:n, :e, :i)"
                ),
                {"n": name, "e": kg, "i": impact_band(kg)},
            )
        for category, kg in categories.items():
            conn.execute(
                text(
                    f'INSERT INTO {SCHEMA}."CategoryEmissions" ("Category","Emissions","Impact") '
                    "VALUES (:c, :e, :i)"
                ),
                {"c": category, "e": kg, "i": impact_band(kg)},
            )

    with engine.connect() as conn:
        nf = conn.execute(text(f'SELECT COUNT(*) FROM {SCHEMA}."FoodEmissions"')).scalar()
        nc = conn.execute(text(f'SELECT COUNT(*) FROM {SCHEMA}."CategoryEmissions"')).scalar()
        print(f"\nFoodEmissions    : {nf} rows")
        print(f"CategoryEmissions: {nc} rows")
        print("\ncategories, kg CO2e per kg:")
        for c, e, i in conn.execute(
            text(f'SELECT "Category","Emissions","Impact" FROM {SCHEMA}."CategoryEmissions" ORDER BY "Emissions" DESC')
        ):
            print(f"  {c:<12}{e:>8.2f}  {i}")


if __name__ == "__main__":
    main()
