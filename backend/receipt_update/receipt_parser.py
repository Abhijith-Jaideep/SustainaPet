# receipt_parser.py
import re, json, pathlib
from typing import List, Dict, Optional
from google.cloud import vision
# receipt_parser.py
import os, json
from pathlib import Path
from typing import Optional, List, Dict
from google.cloud import vision
from google.oauth2 import service_account

def _make_vision_client(key_path: Optional[str] = None) -> vision.ImageAnnotatorClient:
    """
    Prefer GOOGLE_APPLICATION_CREDENTIALS_JSON (inline JSON),
    otherwise resolve GOOGLE_APPLICATION_CREDENTIALS (file path).
    If relative, resolve from the project root (parent of backend/).
    Otherwise use default application credentials.
    """
    # 1) Inline JSON (best for hosted envs without a file)
    inline = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS_JSON")
    if inline:
        info = json.loads(inline)
        creds = service_account.Credentials.from_service_account_info(info)
        return vision.ImageAnnotatorClient(credentials=creds)

    # 2) File path (env or argument). Resolve relative to repo root.
    path = key_path or os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if path:
        if not os.path.isabs(path):
            # project root = parent of backend/
            base = Path(__file__).resolve().parents[1]
            path = str((base / path).resolve())
        if Path(path).exists():
            return vision.ImageAnnotatorClient.from_service_account_file(path)

    # 3) Default credentials (GKE/Cloud Run/Compute Engine, etc.)
    return vision.ImageAnnotatorClient()


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

    # group words into lines by y proximity, then left-to-right
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
# Allow optional minus (or unicode dashes) before price.
SIGNED_MONEY_ANY  = re.compile(r"[−–—-]?\s*\$?\s*\d+(?:,\d{3})*(?:\.\d{2})")
SIGNED_MONEY_TAIL = re.compile(r"[−–—-]?\s*\$?\s*([0-9]{1,3}(?:,[0-9]{3})|[0-9]+)(?:\.[0-9]{2})\s$")

QTY_LINE    = re.compile(r"^(?:qty|quantity)\s*:?\s*(\d+)\s*@\s*\$?\s*([0-9]+(?:\.[0-9]{2}))", re.I)
WEIGHT_LINE = re.compile(r"\b\d+(?:\.\d+)?\s*(?:kg|g|lb|oz)\s*(?:net)?\s*@\s*\$?\s*\d+(?:\.\d{2})\s*/\s*(?:kg|g|lb|oz)\b", re.I)
DEPT_TAIL   = re.compile(r"\b(F[AB]|TX|TA|TB|A|B)\b\.?$", re.I)

# Never treat these as item name lines
SKIP_NAME_LINE = re.compile(
    r"(?:description\b|subtotal\b|sub\s*total\b|total\b|t\s*o\s*t\s*a\s*l\b|amount due|"
    r"tax invoice|abn|approved|\bvisa\b|credit card|debit|mastercard|auth|ref/seq|"
    r"aid\b|arqc\b|term id|merch id|thank you|offers|coupon|pos\b|trans\b|"
    r"a-taxable|b-taxable|gst|tax\b|change\b|barcode|promotional price|"
    r"total for \d+\s*items?)",
    re.I,
)

# Discount/adjustment markers (Coles/Woolworths & generic)
DISCOUNT_OR_ADJ_LINE = re.compile(
    r"(?:\bsave\b|\bsavings?\b|\bdiscount\b|\bextra\s+discount\b|\bmember price\b|"
    r"\bpromo(?:tion(?:al)?)?\b|\boffer\b|\bmarkdown\b|\bprice\s*drop\b|\bdown\s*down\b|"
    r"\brewards?\b|\beveryday rewards\b|\bflybuys\b|\bfuel discount\b|\bmultibuy\b|"
    r"\bbundle\b|\bdeal\b|\bspend\s*&\s*save\b|\bround(?:ing)?(?:\s*adj(?:ustment)?)?\b|"
    r"\bcashback\b|\brefund\b|\bprice promise\b|\bdisc\b)",
    re.I,
)

# Extra guard to ensure we never emit totals/subtotals/etc as items
FORBIDDEN_ITEM_NAME = re.compile(
    r"(?:^|\b)(subtotal|sub\s*total|total|amount due|balance|change|round(?:ing)?|surcharge|"
    r"cash\s*out|cashout|gst|tax)\b",
    re.I,
)

MARKERS = "#^%*"

def _is_negative_prefix(s: str) -> bool:
    """Quick check for minus markers near a price like '- 1.00' or '−$0.50'."""
    return bool(re.search(r"[−–—-]\s*\$?\s*\d", s))

def _last_price_in_line(s: str) -> Optional[float]:
    hits = SIGNED_MONEY_ANY.findall(s)
    if not hits:
        return None
    txt = hits[-1].replace("$", "").replace(",", "").strip()
    txt = re.sub(r"[−–—]", "-", txt)  # normalize unicode dashes
    try:
        return float(txt)
    except ValueError:
        m = re.search(r"-?\d+(?:\.\d{2})", txt)
        return float(m.group(0)) if m else None

def _remove_price_and_dept(s: str) -> str:
    s = DEPT_TAIL.sub("", s).rstrip()
    hits = list(SIGNED_MONEY_ANY.finditer(s))
    if hits:
        start, end = hits[-1].span()
        s = (s[:start] + s[end:]).strip()
    return s

def _remove_tail_money(s: str) -> str:
    return SIGNED_MONEY_TAIL.sub("", s).rstrip()

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
        if re.search(r"\bdescription\b", ln["text"], re.I):
            start = i + 1
            break
    for i, ln in enumerate(L):
        if re.search(r"(subtotal|sub\s*total|t\s*o\s*t\s*a\s*l|amount due|credit card|visa)", ln["text"], re.I):
            end = i
            break
    return L[start:end]

def _looks_like_discount(s: str) -> bool:
    """True if line smells like a discount/adjustment."""
    return bool(DISCOUNT_OR_ADJ_LINE.search(s)) or _is_negative_prefix(s)

def _next_price_after(idx: int, L: List[Dict], max_look: int = 3) -> Optional[float]:
    """
    Look ahead up to max_look lines for a positive price, skipping lines that are
    just currency symbols or whitespace. Ignore totals/discount-looking lines.
    Handles cases where OCR splits the '$' and the numeric amount onto separate lines.
    """
    looked = 0
    j = idx + 1
    while j < len(L) and looked < max_look:
        txt = L[j]["text"].strip()
        looked += 1
        j += 1

        if not txt:
            continue
        if SKIP_NAME_LINE.search(txt) or _looks_like_discount(txt):
            return None

        # line that is only '$' → peek next line
        if re.fullmatch(r"[\$]+", txt):
            if j < len(L):
                nxt = L[j]["text"].strip()
                if nxt and not _looks_like_discount(nxt) and not SKIP_NAME_LINE.search(nxt):
                    p = _last_price_in_line(nxt)
                    if p is not None and p >= 0:
                        return p
            continue

        p = _last_price_in_line(txt)
        if p is not None and p >= 0 and not re.search(r"(total|amount due|subtotal|sub\s*total|approved|change)", txt, re.I):
            return p

    return None

# =========================
# Core item parser
# =========================
def parse_items_only_from_lines(line_objs: List[Dict]) -> List[Dict]:
    L = _slice_body(line_objs)
    items: List[Dict] = []
    i = 0

    while i < len(L):
        ln = L[i]["text"].strip()

        # Skip blanks, totals/subtotals (even with leading numbers), qty headers, and discounts
        if (not ln
            or SKIP_NAME_LINE.search(ln)
            or re.search(r"^\s*\d+\s*(?:subtotal|sub\s*total|total)\b", ln, re.I)
            or ln.lower().startswith(("qty ", "quantity"))
            or _looks_like_discount(ln)):
            i += 1
            continue

        is_marked_item = ln[0] in MARKERS

        # CASE 1: same-line price OR split-right-column price
        price_any = _last_price_in_line(ln)
        if (is_marked_item or ln[0].isalpha()):
            if price_any is None:
                price_any = _next_price_after(i, L, max_look=3)

            if price_any is not None:
                if not _looks_like_discount(ln) and price_any >= 0:
                    name = _clean_name(_remove_price_and_dept(ln))
                    # Final guard: never emit total/subtotal/etc as an item
                    if name and not FORBIDDEN_ITEM_NAME.search(name):
                        items.append({
                            "name": name,
                            "qty": 1,
                            "unit_price": price_any,
                            "line_total": price_any
                        })
                    i += 1
                    continue

        # CASE 2: name then look ahead
        if is_marked_item or ln[0].isalpha():
            name = _clean_name(ln)
            if FORBIDDEN_ITEM_NAME.search(name):
                i += 1
                continue

            qty = 1
            unit_price = None
            line_total = None

            # quick scan for split price right after the name
            if line_total is None:
                p_next = _next_price_after(i, L, max_look=2)
                if p_next is not None:
                    line_total = p_next

            j = i + 1
            looked = 0
            while j < len(L) and looked < 4:
                nxt = L[j]["text"].strip()
                if not nxt:
                    j += 1; looked += 1; continue
                if SKIP_NAME_LINE.search(nxt) or _looks_like_discount(nxt):
                    break

                # Qty line
                m_qty = QTY_LINE.search(nxt)
                if m_qty:
                    qty = int(m_qty.group(1))
                    unit_price = float(m_qty.group(2))
                    p = _last_price_in_line(nxt)
                    if p is not None and p >= 0:
                        line_total = p
                        j += 1
                        break
                    j += 1; looked += 1
                    continue

                # Weight line
                if WEIGHT_LINE.search(nxt):
                    p = _last_price_in_line(nxt)
                    if p is None and j + 1 < len(L):
                        nxt2 = L[j + 1]["text"].strip()
                        if not _looks_like_discount(nxt2):
                            p = _last_price_in_line(nxt2)
                            if p is not None and p >= 0:
                                j += 1; looked += 1
                    if p is not None and p >= 0:
                        line_total = p
                        j += 1
                        break
                    j += 1; looked += 1
                    continue

                # Plain price-only line (avoid totals/discounts)
                p = _last_price_in_line(nxt)
                if (p is not None and p >= 0
                    and not re.search(r"(total|amount due|subtotal|sub\s*total|approved|change)", nxt, re.I)):
                    line_total = p
                    j += 1
                    break

                # If the next meaningful line looks like a new item, stop looking
                if nxt and (nxt[0].isalpha() or nxt[0] in MARKERS) and not nxt.lower().startswith(("qty ", "quantity")):
                    break

                j += 1; looked += 1

            if line_total is None and unit_price is not None:
                line_total = round(unit_price * qty, 2)
            if unit_price is None and line_total is not None and qty:
                unit_price = round(line_total / qty, 2)

            if name and (unit_price is not None or line_total is not None):
                if (unit_price is None or unit_price >= 0) and (line_total is None or line_total >= 0):
                    items.append({"name": name, "qty": qty, "unit_price": unit_price, "line_total": line_total})
            i = j
            continue

        i += 1

    # Safety net: drop any residual negatives and forbidden names
    clean_items = []
    for it in items:
        if (it.get("unit_price", 0) < 0) or (it.get("line_total", 0) < 0):
            continue
        if FORBIDDEN_ITEM_NAME.search(it.get("name", "")):
            continue
        clean_items.append(it)

    return clean_items

# =========================
# Safe wrappers / Public API
# =========================
def _has_meaningful_text(lines: List[Dict]) -> bool:
    """Small sanity check that OCR returned real text (not just blanks/$)."""
    if not lines:
        return False
    seen = 0
    for ln in lines:
        t = (ln.get("text") or "").strip()
        if not t:
            continue
        if re.fullmatch(r"[\$]+", t):
            continue
        if re.search(r"[A-Za-z0-9]", t):
            seen += 1
            if seen >= 3:
                return True
    return False

def extract_items_from_image_path(image_path: str, key_path: Optional[str] = None) -> List[Dict]:
    """Original high-level helper: path → OCR → parse → items"""
    if not pathlib.Path(image_path).exists():
        raise FileNotFoundError(f"Image not found: {image_path}")
    line_objs = ocr_image_path_to_lines(image_path, key_path=key_path)
    return parse_items_only_from_lines(line_objs)

def extract_items_from_bytes(data: bytes, key_path: Optional[str] = None) -> List[Dict]:
    line_objs = ocr_image_bytes_to_lines(data, key_path=key_path)
    return parse_items_only_from_lines(line_objs)

def extract_items_from_image_path_safe(image_path: str, key_path: Optional[str] = None) -> Dict:
    """
    Safer high-level helper:
      - returns {"items":[...]} on success
      - returns {"error": "..."} when image/ocr/parsing fails
      - returns {"items": [], "message": "no items found"} when OCR ok but no items
    """
    try:
        if not pathlib.Path(image_path).exists():
            return {"error": f"image not found: {image_path}"}

        line_objs = ocr_image_path_to_lines(image_path, key_path=key_path)

        if not _has_meaningful_text(line_objs):
            return {"error": "invalid image or no readable text detected"}

        items = parse_items_only_from_lines(line_objs)
        if not items:
            return {"items": [], "message": "no items found"}
        return {"items": items}

    except Exception as e:
        return {"error": "invalid image or OCR error", "details": str(e)}

# =========================
# CLI (safe + optional debug)
# =========================
if __name__ == "_main_":
    import sys, os

    if len(sys.argv) < 2:
        print("Usage: python receipt_parser.py <image_path> [key_path] [--debug]")
        raise SystemExit(1)

    img = sys.argv[1]
    key = None
    debug = False
    for arg in sys.argv[2:]:
        if arg == "--debug":
            debug = True
        elif not arg.startswith("--"):
            key = arg

    result = extract_items_from_image_path_safe(img, key_path=key)

    if debug and ("error" in result or (isinstance(result.get("items"), list) and not result["items"])):
        try:
            line_objs = ocr_image_path_to_lines(img, key_path=key)
            print("\n# ---- OCR LINES (first 40) ----")
            for i, ln in enumerate(line_objs[:40]):
                print(f"{i:>3}: {ln.get('text','').strip()}")
        except Exception as e:
            print("# (debug) OCR failed to dump lines:", e)

    print(json.dumps(result, indent=2))