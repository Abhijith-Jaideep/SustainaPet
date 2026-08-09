#!/usr/bin/env python
# coding: utf-8

# In[1]:


import re, numpy as np, pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from nltk.stem import WordNetLemmatizer
from sentence_transformers import SentenceTransformer, util

import nltk
import os 
from nltk.stem import WordNetLemmatizer

nltk.data.path.append(
    os.path.join(os.path.dirname(__file__), "..", "nltk_data")
)
try:
    _ = WordNetLemmatizer().lemmatize("test")
except LookupError:
    raise RuntimeError(
        "WordNet not found. Ensure nltk_data/corpora/wordnet and omw-1.4 are in the repo."
    )

# In[ ]:


lemmatizer = WordNetLemmatizer()
UNIT_PATTERN = re.compile(r"(\d+(?:\.\d+)?)(?:\s?x\s?)?(\s?kg|\s?g|\s?l|\s?ml|pk)", re.IGNORECASE)
UNIT_PRIORITY = {"ml": 5, "l": 4, "g": 3, "kg": 2, "pk": 1}

def extract_weight_kg(item: str) -> float:
    """Extract weight/volume from item string and return in kg.
    - ml treated as grams (1ml = 1g).
    - pk treated as 100g (0.1kg) per pack.
    """
    matches = UNIT_PATTERN.findall(item.lower())
    if not matches:
        return 1.0

    total_kg = 0.0
    for val, unit in matches:
        val = float(val)
        unit = unit.strip().lower()
        if unit == "kg":
            total_kg += val
        elif unit == "g":
            total_kg += val / 1000
        elif unit == "l":
            total_kg += val
        elif unit == "ml":
            total_kg += val / 1000
        elif unit == "pk":
            total_kg += val * 0.1  # 100g each
    return total_kg

def clean_units(text: str) -> str:
    """
    Fix common OCR/unit typos before regex.
    - 'm1', 'mi', 'mI' → 'ml'
    - standalone 'm' after number → 'ml'
    """
    text = text.lower()
    text = re.sub(r"(\d+)\s*m1\b", r"\1ml", text)
    text = re.sub(r"(\d+)\s*mi\b", r"\1ml", text)
    text = re.sub(r"(\d+)\s*m\b", r"\1ml", text)
    return text


def extract_display_qty(item: str, qty: float) -> str:
    """
    Create a display quantity string with unit priority:
    ml > l > g > kg > pk
    - If no number with 'pk' → use receipt qty
    """
    clean_item = clean_units(item)
    matches = UNIT_PATTERN.findall(clean_item)

    if matches:
        # pick the highest priority unit
        best_val, best_unit = max(matches, key=lambda x: UNIT_PRIORITY[x[1].lower()])
        base = f"{best_val}{best_unit}"
        return f"{int(qty)} x {base}" if qty > 1 else base
    else:
        # fallback to pk with receipt qty
        return f"{int(qty)}pk"
    
# -----------------------------------
# Helpers
# -----------------------------------
def normalize_name(name: str) -> str:
    if pd.isna(name):
        return ""
    name = name.lower()
    name = re.sub(r"[^a-z\s]", " ", name)
    name = re.sub(r"\s+", " ", name).strip()
    tokens = [lemmatizer.lemmatize(w, pos="n") for w in name.split()]
    return " ".join(tokens)

def json_to_df(receipt_json):
    df = pd.DataFrame(receipt_json["items"])
    df = df.rename(columns={"name": "Item", "qty": "Qty", "unit_price": "UnitPrice", "line_total": "LineTotal"})
    df["NormalizedName"] = df["Item"].map(normalize_name)
    return df

# -----------------------------------
# Build TF-IDF index from df_emissions
# -----------------------------------
def build_index_from_emissions(df_emissions: pd.DataFrame, name_col="Name"):
    names = df_emissions[name_col].apply(normalize_name).tolist()
    index = {normalize_name(row[name_col]): row.to_dict()
             for _, row in df_emissions.iterrows()}
    vectorizer = TfidfVectorizer().fit(names)
    tfidf_matrix = vectorizer.transform(names)
    return {
        "index": index,
        "names": names,
        "vectorizer": vectorizer,
        "tfidf_matrix": tfidf_matrix,
        "rows": [row.to_dict() for _, row in df_emissions.iterrows()]
    }

# -----------------------------------
# Build semantic category index
# -----------------------------------
def build_category_index(categories, model_name="all-MiniLM-L6-v2", device=None):
    model = SentenceTransformer(model_name, device=device)
    labels = [normalize_name(c) for c in categories]
    emb = model.encode(labels, normalize_embeddings=True)
    return {"model": model, "emb": emb, "labels": categories}

# -----------------------------------
# Map single item
# -----------------------------------
def map_item(item: str, items_index, cat_index, df_emissions, df_category_emissions, cutoff=0.4, threshold=0.60):
    norm_item = normalize_name(item)
    match, confidence, method = None, 0.0, "None"

    # --- Exact match ---
    if norm_item in items_index["index"]:
        match = items_index["index"][norm_item]
        confidence, method = 1.0, "Exact"

    else:
        # --- TF-IDF lexical ---
        vec = items_index["vectorizer"].transform([norm_item])
        sims = cosine_similarity(vec, items_index["tfidf_matrix"]).flatten()
        best_score = sims.max()
        if best_score >= cutoff:
            i = int(np.argmax(sims))
            match = items_index["rows"][i]
            confidence, method = float(best_score), "TFIDF"

    # --- Semantic fallback ---
    Category, cat_conf = None, 0.0
    if confidence < threshold:
        q = cat_index["model"].encode([norm_item], normalize_embeddings=True)
        sims = util.cos_sim(q, cat_index["emb"])[0].cpu().numpy()
        j = int(np.argmax(sims))
        Category, cat_conf = cat_index["labels"][j], float(sims[j])
        confidence, method = cat_conf, "SemanticCategory"

    # --- Output ---
    if method in ["Exact", "TFIDF"]:
        return {
            "Item": item,
            "MatchedName": match["Name"] if match else None,
            "Emissions": match["Emissions"] if match else None,
            "Impact": match.get("Impact") if match else None,
            "Confidence": confidence,
            "Method": method,
            "Category": None
        }
    else:
        row = df_category_emissions.loc[df_category_emissions["Category"] == Category]
        emissions = float(row["Emissions"].values[0]) if not row.empty else 3.0
        impact = row["Impact"].values[0] if not row.empty else None
        return {
            "Item": item,
            "MatchedName": Category,
            "Emissions": emissions,
            "Impact": impact, 
            "Confidence": confidence,
            "Method": method,
            "Category": Category
        }

# -----------------------------------
# Map full receipt
# -----------------------------------
def map_receipt_with_emissions(receipt_json, items_index, cat_index, df_emissions, df_category_emissions):
    receipt_df = json_to_df(receipt_json)
    mapped = [map_item(x, items_index, cat_index, df_emissions, df_category_emissions) 
              for x in receipt_df["Item"]]
    mapped_df = pd.DataFrame(mapped)

    # Merge receipt + mapping
    final = receipt_df.merge(mapped_df, on="Item", how="left")

    # Weight extraction
    final["WeightKG"] = final["Item"].map(extract_weight_kg)

    # Human-readable Qty column
    final["DisplayQty"] = [
    extract_display_qty(item, qty) for item, qty in zip(final["Item"], final["Qty"])
    ]


    # Total emissions
    final["TotalEmissions"] = final["Qty"] * final["WeightKG"] * final["Emissions"]

    return final[["Item", "DisplayQty", "WeightKG", "MatchedName", 
              "Emissions", "TotalEmissions", "Impact", "Confidence", "Method"]]

# In[3]:


import os
import pandas as pd
from sqlalchemy import create_engine


# This block used to run at import time against a connection string with the
# database password written into it. Two problems: the credential was in the
# source of a public repository, and merely importing this module opened a
# database connection and ran two queries, so anything that touched it needed
# a live database.
#
# The URL now comes from the environment, and the indices are built on first
# use rather than on import.
def _engine():
    url = os.environ.get("DATABASE_URL")
    if not url:
        raise RuntimeError(
            "DATABASE_URL is not set. Expected a SQLAlchemy Postgres URL, for "
            "example postgresql+psycopg2://user:pass@host:5432/dbname"
        )
    return create_engine(url)


_indices = None


def get_indices():
    """Load the emissions reference tables and build the lookup indices once."""
    global _indices
    if _indices is None:
        engine = _engine()
        df_emissions = pd.read_sql('SELECT * FROM sustainapet."FoodEmissions";', engine)
        df_category_emissions = pd.read_sql(
            'SELECT * FROM sustainapet."CategoryEmissions";', engine
        )
        _indices = {
            "df_emissions": df_emissions,
            "df_category_emissions": df_category_emissions,
            "items_index": build_index_from_emissions(df_emissions, name_col="Name"),
            "cat_index": build_category_index(list(df_category_emissions["Category"])),
        }
    return _indices


# In[7]:



