from google.cloud import vision

client = vision.ImageAnnotatorClient()

with open("eReceipt_3806_Clayton_08Jun2025__olvey_page-0001.jpg", "rb") as f:
    image = vision.Image(content=f.read())

response = client.document_text_detection(image=image)
full = response.full_text_annotation

print("FULL TEXT:\n", full.text)  # richer than text_annotations[0].description

# quick-and-dirty line-item extraction (regex tweak as you like)
import re
lines = full.text.splitlines()
item_lines = []
for ln in lines:
    # example patterns: lines starting with # or containing a trailing price
    if ln.strip().startswith("#") or re.search(r"\b\d+\.\d{2}$", ln.strip()):
        item_lines.append(ln.strip())

print("\nLIKELY LINE ITEMS:")
for x in item_lines:
    print("-", x)

if response.error.message:
    raise RuntimeError(response.error.message)
