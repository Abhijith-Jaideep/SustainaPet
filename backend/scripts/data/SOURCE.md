# food-emissions-supply-chain.csv

Greenhouse gas emissions per kilogram of food product, broken down by supply
chain stage. 43 food products.

**Source:** Our World in Data, "Environmental impacts of food production",
grapher slug `food-emissions-supply-chain`, retrieved 9 August 2026 from
<https://ourworldindata.org/grapher/food-emissions-supply-chain.csv>

**Underlying study:** Poore, J. and Nemecek, T. (2018). "Reducing food's
environmental impacts through producers and consumers." *Science* 360(6392),
987-992.

**Licence:** Creative Commons BY 4.0. Attribution required, redistribution
permitted.

## Why it is committed here

The original `FoodEmissions` and `CategoryEmissions` tables existed only inside
a hosted database with no schema, no seed and no recorded provenance. When that
server was deleted the data was unrecoverable and the project could not be
revived. Keeping the source data in the repository means the database can
always be rebuilt from scratch.

Columns are per-stage emissions in kg CO2-equivalent per kg of product. The
total for a product is the sum of the stage columns, which is what
`seed_emissions.py` loads.
