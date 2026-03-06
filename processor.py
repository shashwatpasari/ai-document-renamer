import json
import re
import shutil
import tempfile
from datetime import datetime
from pathlib import Path

import fitz  # PyMuPDF
import ollama
import config

# Simple instructions for the AI model.
PROMPT = """Look at this document and extract:
1. Document type (bank statement, invoice, payslip, etc.)
2. Full name of the person this belongs to
3. Organisation name (bank, company, etc.)
4. Month and year of the document (March 2025, June 2026)

Formatting rules:
- Name must be in Title Case (e.g. "Shashwat Pasari", not "SHASHWAT PASARI" or "shashwat pasari")
- Organisation must use proper casing. Keep acronyms uppercase (e.g. "ANZ", "CBA", "NAB", "ATO"). Use Title Case for full names (e.g. "Commonwealth Bank Of Australia")
- Document type in lowercase (e.g. "bank statement", "payslip")

Return ONLY valid json, nothing else:
{"type": "...", "name": "...", "org": "...", "month": "...", "year": "..."}
Use null if a field is not found.
Month must be a number from 1 to 12.
Year must be four digits.
"""

MONTH_MAP = {
    "jan": 1, "january": 1,
    "feb": 2, "february": 2,
    "mar": 3, "march": 3,
    "apr": 4, "april": 4,
    "may": 5,
    "jun": 6, "june": 6,
    "jul": 7, "july": 7,
    "aug": 8, "august": 8,
    "sep": 9, "september": 9,
    "oct": 10, "october": 10,
    "nov": 11, "november": 11,
    "dec": 12, "december": 12,
}

def sanitize(text):
    # Clean invalid filename characters.
    if not text:
        return None
    cleaned = re.sub(f'[<>:"/\\|?*]', "", str(text)).strip()
    return cleaned or None

def normalize_month(value):
    # Convert month text/number into 1..12.
    if not value:
        return None
    if isinstance(value, int):
        return value if 1 <= value <= 12 else None

    s = str(value).strip().lower()
    if s.isdigit():
        m = int(s)
        return m if 1 <= m <= 12 else None
    
    return MONTH_MAP.get(s)

def normalize_year(value):
    if not value:
        return None
    if isinstance(value, int):
        return value if 1000 <= value <= 2100 else None
    
    s = str(value).strip()
    if not s.isdigit():
        return None
    y = int(s)
    return y if 1000 <= y <= 2100 else None
   

def parse_llm_response(text):
    # Parse model JSON safely.
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if not match:
            data = {}
        else:
            try:
                data = json.loads(match.group(0))
            except json.JSONDecodeError:
                data = {}

    if not isinstance(data, dict):
        data = {}

    return {
        "type": sanitize(data.get("type")),
        "name": sanitize(data.get("name")),
        "org": sanitize(data.get("org")),
        "month": normalize_month(data.get("month")),
        "year": normalize_year(data.get("year")),
    }

def pdf_to_images(pdf_path, dpi=200):
    # Convert all PDF pages to temporary JPG files.
    doc = fitz.open(pdf_path)
    image_paths = []
    try:
        for i, page in enumerate(doc):
            pix = page.get_pixmap(dpi=dpi)
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix=f"_page_{i+1}.jpg")
            tmp_path = tmp.name
            tmp.close()
            pix.save(tmp_path)
            image_paths.append(tmp_path)
    finally:
        doc.close()
    return image_paths

def ask_qwen_images(image_paths):
    # Send all page images together for OCR
    response = ollama.chat(
        model=config.MODEL,
        messages=[{"role": "user", "content": PROMPT, "images": image_paths}],
    )
    return parse_llm_response(response["message"]["content"])

def get_period(info):
    # Use extracted year/month. If missing, fallback to current month.
    year = info.get("year")
    month = info.get("month")
    if year and month:
        try: 
            return datetime(year, month, 1).strftime("%B %Y")
        except ValueError:
            pass
    # Fallback to current month/year if missing or invalid.
    return datetime.now().strftime("%B %Y")

def get_output_folder(info):
    # Create monthly output folder.
    folder = Path(config.OUTPUT_FOLDER) / get_period(info)
    folder.mkdir(parents=True, exist_ok=True)
    return folder

def build_filename(info, ext):
    # Build final file name with consistent Title Case.
    name = sanitize(info.get("name"))
    org = sanitize(info.get("org"))
    doc_type = sanitize(info.get("type"))

    if name and org:
        base = f"{name} - {org}"
    elif name:
        base = name
    elif org:
        base = org
    else:
        # If both name and org are missing but doc_type exists, just use doc_type
        base = doc_type

    if not base:
        return None

    # Append doc_type to the end if we have a name/org
    if doc_type and base != doc_type:
        base = f"{base} - {doc_type}"

    return f"{base}{ext}"

def unique_destination(path):
    # Avoid overwrite by adding (1), (2), etc.
    if not path.exists():
        return path

    stem = path.stem
    suffix = path.suffix
    parent = path.parent
    i = 1
    while True:
        candidate = parent / f"{stem} ({i}){suffix}"
        if not candidate.exists():
            return candidate
        i += 1

def process(file_path):
    # Process a single file.
    src = Path(file_path)
    ext = src.suffix.lower()
    
    info = {"type": None, "name": None, "org": None, "month": None, "year": None}
    temp_images = []

    try:
        if ext == ".pdf":
            # OCR path only: convert all pages to images, send all images to model.
            temp_images = pdf_to_images(src)
            info = ask_qwen_images(temp_images)
        else:
            # Image files also use OCR/vision path.
            info = ask_qwen_images([str(src)])
    finally:
        # Clean up temporary images.
        for p in temp_images:
            try:
                Path(p).unlink(missing_ok=True)
            except Exception:
                pass

    new_name = build_filename(info, ext)
    if not new_name:
        print(f"Skipped (missing name/org/type): {src.name}")
        return False

    out_folder = get_output_folder(info)
    dst = out_folder / new_name
    dst = unique_destination(dst)

    if config.DRY_RUN:
        print(f"[DRY RUN] {src} -> {dst}")
        return True

    shutil.copy2(src, dst)
    print(f"Copied: {src.name} -> {dst.name}")
    return True

def process_all():
    # Process all files in the input folder.
    input_folder = Path(config.INPUT_FOLDER)
    if not input_folder.exists():
        print(f"Input folder does not exist: {input_folder}")
        return

    allowed = {e.lower() for e in config.SUPPORTED_EXTENSIONS}
    files = [p for p in input_folder.rglob("*") if p.is_file() and p.suffix.lower() in allowed]

    if not files:
        print("No supported files found.")
        return

    ok = 0
    fail = 0

    for f in files:
        try: 
            if process(f):
                ok += 1
            else:
                fail += 1
        except Exception as ex:
            fail += 1
            print(f"Error on {f.name}: {ex}")

    print(f"Done. Success: {ok}, Failed/Skipped: {fail}")


    
            