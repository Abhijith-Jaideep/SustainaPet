from flask import Flask, request, jsonify
from .ItemToDataset import map_receipt_with_emissions, build_index_from_emissions, build_category_index

import pandas as pd

from .ItemToDataset import (
    map_receipt_with_emissions,
    build_index_from_emissions,
    build_category_index,
    df_emissions,
    df_category_emissions
)

# def map_receipt():
#     '''
#         input:Json
#         output: the information list includes:
#         {
#             item
#             weightkg
#             qty
#             matched_name
#             total_emissions
#         }
#     '''
#     receipt_json = request.get_json()  # recieve OCR print JSON
    
#     # call the function，retrieve the DataFrame
#     df_result = map_receipt_with_emissions(receipt_json, food_index, category_index, df_emissions, df_category_emissions)
    
#     # keep the field that needed
#     df_filtered = df_result[["Item", "WeightKG", "Qty", "MatchedName", "TotalEmissions"]]
    
#     # transform to JSON
#     json_result = df_filtered.to_dict(orient="records")
    
#     return jsonify(json_result)

def map_receipt(receipt_json, food_index, category_index, df_emissions, df_category_emissions):
    """
    input: receipt_json (dict)
    output: DataFrame with columns:
        Item, WeightKG, Qty, MatchedName, TotalEmissions
    """
    df_result = map_receipt_with_emissions(receipt_json, food_index, category_index, df_emissions, df_category_emissions)
    df_filtered = df_result[["Item", "WeightKG", "Qty", "MatchedName", "TotalEmissions"]]
    return df_filtered
    