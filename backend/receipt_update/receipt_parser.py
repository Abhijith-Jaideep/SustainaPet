# receipt_parser.py
import re, json, pathlib
from typing import List, Dict, Optional
from google.cloud import vision

# =========================
# Vision client factory
# =========================
def _make_vision_client(key_path: Optional[str] = None) -> vision.ImageAnnotatorClient:
    """
    Returns an ImageAnnotatorClient. If key_path is provided, uses that service-account
    key file directly; otherwise falls back to default credentials / env var.
    """
    if key_path:
        return vision.ImageAnnotatorClient.from_service_account_file(key_path)
    return vision.ImageAnnotatorClient()

# =========================
# OCR → words → lines
# =========================
def _word_center_y(verts) -> float:
    return sum(v.y for v in verts) / 4.0

def _word_min_x(verts) -> float:
    return min(v.x for v in verts)

def _word_max_x(verts) -> float:
    return max(v.x for v in verts)

def _ocr_bytes_to_lines(data: bytes, client: vision.ImageAnnotatorClient) -> List[Dict]:
    """Rebuild lines from word boxes."""
    resp = client.document_text_detection(image=vision.Image(content=data))
    if resp.error.message:
        raise RuntimeError(resp.error.message)

    words = []
    fta = resp.full_text_annotation
    for page in fta.pages:
        for block in page.blocks:
            for para in block.paragraphs:
                for word in para.words:
                    txt = "".join(sym.text for sym in word.symbols)
                    if not txt.strip():
                        continue
                    words.append({
                        "text": txt,
                        "y": _word_center_y(word.bounding_box.vertices),
                        "xmin": _word_min_x(word.bounding_box.vertices),
                        "xmax": _word_max_x(word.bounding_box.vertices),
                    })

    words.sort(key=lambda w: (round(w["y"]), w["xmin"]))
    lines: List[Dict] = []
    y_threshold = 12.0
    current: List[Dict] = []
    current_y = None

    def _flush():
        if not current:
            return
        current.sort(key=lambda t: t["xmin"])
        lines.append({
            "text": " ".join(t["text"] for t in current).strip(),
            "y": current_y,
            "xmin": min(t["xmin"] for t in current),
            "xmax": max(t["xmax"] for t in current),
        })

    for w in words:
        if current_y is None or abs(w["y"] - current_y) <= y_threshold:
            current.append(w)
            current_y = w["y"] if current_y is None else (current_y * 0.7 + w["y"] * 0.3)
        else:
            _flush()
            current, current_y = [w], w["y"]
    _flush()

    lines.sort(key=lambda L: L["y"])
    return lines

# Convenience wrappers
def ocr_image_path_to_lines(image_path: str, key_path: Optional[str] = None) -> List[Dict]:
    client = _make_vision_client(key_path)
    with open(image_path, "rb") as f:
        data = f.read()
    return _ocr_bytes_to_lines(data, client)

def ocr_image_bytes_to_lines(data: bytes, key_path: Optional[str] = None) -> List[Dict]:
    client = _make_vision_client(key_path)
    return _ocr_bytes_to_lines(data, client)

# =========================
# Parsing helpers
# =========================
MONEY_ANY = re.compile(r"\$?\s*\d+(?:,\d{3})*(?:\.\d{2})")
MONEY_TAIL = re.compile(r"\$?\s*([0-9]{1,3}(?:,[0-9]{3})*|[0-9]+)(?:\.[0-9]{2})\s*$")
QTY_LINE   = re.compile(r"^(?:qty|quantity)\s*:?\s*(\d+)\s*@\s*\$?\s*([0-9]+(?:\.[0-9]{2}))", re.I)
WEIGHT_LINE = re.compile(r"\b\d+(?:\.\d+)?\s*(?:kg|g|lb|oz)\s*(?:net)?\s*@\s*\$?\s*\d+(?:\.\d{2})\s*/\s*(?:kg|g|lb|oz)\b", re.I)
DEPT_TAIL = re.compile(r"\b(F[AB]|TX|TA|TB|A|B)\b\.?$", re.I)
SKIP_NAME_LINE = re.compile(
    r"(?:^description\b|^subtotal\b|^total\b|^t\s*o\s*t\s*a\s*l\b|amount due|"
    r"tax invoice|abn|approved|\bvisa\b|credit card|debit|mastercard|auth|ref/seq|"
    r"aid\b|arqc\b|term id|merch id|thank you|offers|coupon|pos\b|trans\b|"
    r"a-taxable|b-taxable|gst|tax\b|change\b|barcode|promotional price|"
    r"^total for \d+ items\b)",
    re.I,
)
MARKERS = "#^%*"

def _last_price_in_line(s: str) -> Optional[float]:
    hits = MONEY_ANY.findall(s)
    if not hits:
        return None
    val = hits[-1]
    return float(val.replace("$", "").replace(",", "").strip())

def _remove_price_and_dept(s: str) -> str:
    s = DEPT_TAIL.sub("", s).rstrip()
    hits = list(MONEY_ANY.finditer(s))
    if hits:
        start, end = hits[-1].span()
        s = (s[:start] + s[end:]).strip()
    return s

def _remove_tail_money(s: str) -> str:
    return MONEY_TAIL.sub("", s).rstrip()

def _clean_name(s: str) -> str:
    s = s.strip()
    s = re.sub(rf"^[{re.escape(MARKERS)}\-\•\s]+", "", s)
    s = re.sub(r"\s{2,}", " ", s)
    return s.strip(" ,-/").strip()

def _slice_body(lines: List[Dict]) -> List[Dict]:
    L = [ln for ln in lines if ln.get("text")]
    start = 0
    end = len(L)
    for i, ln in enumerate(L):
        if ln["text"].lower().startswith("description"):
            start = i + 1
            break
    for i, ln in enumerate(L):
        if re.search(r"(subtotal|^t\s*o\s*t\s*a\s*l\b|amount due|credit card|visa)", ln["text"], re.I):
            end = i
            break
    return L[start:end]

# =========================
# Core item parser (unchanged logic you tested)
# =========================
def parse_items_only_from_lines(line_objs: List[Dict]) -> List[Dict]:
    L = _slice_body(line_objs)
    items: List[Dict] = []
    i = 0

    while i < len(L):
        ln = L[i]["text"].strip()
        if not ln or SKIP_NAME_LINE.search(ln) or ln.lower().startswith(("qty ", "quantity")):
            i += 1
            continue

        is_marked_item = ln[0] in MARKERS

        # CASE 1: same-line price anywhere (ALDI style '3.99 FA')
        price_any = _last_price_in_line(ln)
        if price_any is not None and (is_marked_item or ln[0].isalpha()):
            name = _clean_name(_remove_price_and_dept(ln))
            if name:
                items.append({"name": name, "qty": 1, "unit_price": price_any, "line_total": price_any})
            i += 1
            continue

        # CASE 2: name then look ahead
        if is_marked_item or ln[0].isalpha():
            name = _clean_name(ln)
            qty = 1
            unit_price = None
            line_total = None

            j = i + 1
            looked = 0
            while j < len(L) and looked < 4:
                nxt = L[j]["text"].strip()
                if not nxt:
                    j += 1; looked += 1; continue
                if SKIP_NAME_LINE.search(nxt):
                    break

                # Qty line
                m_qty = QTY_LINE.search(nxt)
                if m_qty:
                    qty = int(m_qty.group(1))
                    unit_price = float(m_qty.group(2))
                    p = _last_price_in_line(nxt)
                    if p is not None:
                        line_total = p
                        j += 1
                        break
                    j += 1; looked += 1
                    continue

                # Weight line (price here or next line)
                if WEIGHT_LINE.search(nxt):
                    p = _last_price_in_line(nxt)
                    if p is None and j + 1 < len(L):
                        nxt2 = L[j + 1]["text"].strip()
                        p = _last_price_in_line(nxt2)
                        if p is not None:
                            j += 1; looked += 1
                    if p is not None:
                        line_total = p
                        j += 1
                        break
                    j += 1; looked += 1
                    continue

                # Plain price-only line (avoid totals)
                p = _last_price_in_line(nxt)
                if p is not None and not re.search(r"(total|amount due|subtotal|approved|change)", nxt, re.I):
                    line_total = p
                    j += 1
                    break

                if nxt and (nxt[0].isalpha() or nxt[0] in MARKERS) and not nxt.lower().startswith(("qty ", "quantity")):
                    break

                j += 1; looked += 1

            if line_total is None and unit_price is not None:
                line_total = round(unit_price * qty, 2)
            if unit_price is None and line_total is not None and qty:
                unit_price = round(line_total / qty, 2)

            if name and (unit_price is not None or line_total is not None):
                items.append({"name": name, "qty": qty, "unit_price": unit_price, "line_total": line_total})
            i = j
            continue

        i += 1

    return items

# =========================
# Public API (call these from your app/tests)
# =========================
def extract_items_from_image_path(image_path: str, key_path: Optional[str] = None) -> List[Dict]:
    """High-level helper: path → OCR → parse → items"""
    if not pathlib.Path(image_path).exists():
        raise FileNotFoundError(f"Image not found: {image_path}")
    line_objs = ocr_image_path_to_lines(image_path, key_path=key_path)
    return parse_items_only_from_lines(line_objs)

def extract_items_from_bytes(data: bytes, key_path: Optional[str] = None) -> List[Dict]:
    line_objs = ocr_image_bytes_to_lines(data, key_path=key_path)
    return parse_items_only_from_lines(line_objs)

# (Optional) keep a tiny CLI for ad-hoc testing
if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: python receipt_parser.py <image_path> [key_path]")
        raise SystemExit(1)
    img = sys.argv[1]
    key = sys.argv[2] if len(sys.argv) > 2 else None
    print(json.dumps(extract_items_from_image_path(img, key_path=key), indent=2))
