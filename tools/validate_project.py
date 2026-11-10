#!/usr/bin/env python3
"""
CarPlayPlus project consistency validator.

Checks (all local, no Theos toolchain required):
  1. every .plist is well-formed XML and parseable by plistlib
  2. every `loadSpecifiersFromPlistName:@"X"` in *.m has `Resources/X.plist`
  3. every controller `detail` class listed in plists is implemented in *.m
  4. every `cellClass` listed in plists is declared in Cells.h
  5. every `action` referenced by plists exists in the controller sources
  6. rough brace/paren balance on .m/.xm/.h files
  7. `SUBPROJECTS` in the root Makefile all exist

Run:  python3 tools/validate_project.py
"""

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ERRORS = []


def error(msg: str) -> None:
    ERRORS.append(msg)


# --------------------------------------------------------------------------
# 1. Plist well-formedness
# --------------------------------------------------------------------------
plists = sorted((ROOT / "Preferences" / "Resources").glob("*.plist")) + \
         sorted((ROOT / "layout").rglob("*.plist")) + \
         [ROOT / "CarPlayPlus.plist"]

for p in plists:
    try:
        with open(p, "rb") as fh:
            plistlib.load(fh)
    except Exception as exc:  # noqa: BLE001
        error(f"[plist] {p.relative_to(ROOT)}: {exc}")

# Controller sources
controller_sources = [
    ROOT / "Preferences" / "CarPlayPlusRootListController.m",
    ROOT / "Preferences" / "Controllers" / "Controllers.m",
]
cell_header = ROOT / "Preferences" / "Cells" / "Cells.h"

joined_sources = "\n".join(
    s.read_text(encoding="utf-8", errors="replace") for s in controller_sources
)


def source_has(name: str) -> bool:
    return bool(re.search(r"\b" + re.escape(name) + r"\b", joined_sources))


# --------------------------------------------------------------------------
# 2. loadSpecifiersFromPlistName references
# --------------------------------------------------------------------------
for src in controller_sources:
    text = src.read_text(encoding="utf-8", errors="replace")
    for match in re.finditer(r'loadSpecifiersFromPlistName:@"([^"]+)"', text):
        name = match.group(1)
        if not (ROOT / "Preferences" / "Resources" / f"{name}.plist").exists():
            error(f"[specifiers] {src.name} -> missing Resources/{name}.plist")

# --------------------------------------------------------------------------
# 3-5. Specifier cross-references
# --------------------------------------------------------------------------
cell_classes = set(re.findall(r"@interface\s+(\w+)\s*:", cell_header.read_text(
    encoding="utf-8", errors="replace")))

for p in (ROOT / "Preferences" / "Resources").glob("*.plist"):
    with open(p, "rb") as fh:
        data = plistlib.load(fh)
    items = data.get("items") or data.get("specifiers") or []
    for spec in items:
        if not isinstance(spec, dict):
            continue
        detail = spec.get("detail")
        if detail:
            if not source_has(detail):
                error(f"[detail] {p.name}: `{detail}` not implemented in controllers")
        cell_class = spec.get("cellClass")
        if cell_class:
            if cell_class not in cell_classes:
                error(f"[cellClass] {p.name}: `{cell_class}` not declared in Cells.h")
        action = spec.get("action")
        if action:
            sel = action.rstrip(":")
            if sel and not source_has(sel):
                error(f"[action] {p.name}: method `{sel}` not found in controllers")
        # options used by CarPlayPlusStylePickerCell must carry appearanceOption
        if spec.get("options"):
            for opt in spec.get("options", []):
                if "appearanceOption" not in opt:
                    error(f"[options] {p.name}: option missing appearanceOption")

# PreferenceLoader entry must reference an existing bundle/detail
loader = ROOT / "layout/Library/PreferenceLoader/Preferences/CarPlayPlus.plist"
if loader.exists():
    with open(loader, "rb") as fh:
        entry = plistlib.load(fh).get("entry", {})
    if not source_has(entry.get("detail", "")):
        error(f"[preferenceloader] detail `{entry.get('detail')}` not implemented")
else:
    error("[preferenceloader] layout/Library/PreferenceLoader/Preferences/CarPlayPlus.plist missing")

# --------------------------------------------------------------------------
# 6. Brace / paren balance
# --------------------------------------------------------------------------
def balance(text: str, open_ch: str, close_ch: str) -> int:
    return text.count(open_ch) - text.count(close_ch)

for path in list(ROOT.glob("Tweak/*.{xm,h,m}")) + \
            list(ROOT.glob("Preferences/**/*.{m,h}")) + \
            list(ROOT.glob("IconsGenerator/*.{m,h}")):
    text = path.read_text(encoding="utf-8", errors="replace")
    # strip comments and strings crudely to avoid false positives on @"..." / //...
    stripped = re.sub(r"//[^\n]*", "", text)
    stripped = re.sub(r'/\*.*?\*/', "", stripped, flags=re.DOTALL)
    stripped = re.sub(r'@"(?:\\.|[^"\\])*"', '""', stripped)
    stripped = re.sub(r"'(?:\\.|[^'\\])*'", "''", stripped)
    for op, cl in (("{", "}"), ("(", ")"), ("[", "]")):
        diff = balance(stripped, op, cl)
        if diff != 0:
            error(f"[balance] {path.relative_to(ROOT)}: `{op}{cl}` imbalance ({diff:+d})")

# --------------------------------------------------------------------------
# 7. SUBPROJECTS exist
# --------------------------------------------------------------------------
makefile = ROOT / "Makefile"
subproj = re.findall(r"SUBPROJECTS\s*\+?=\s*(.+)", makefile.read_text(encoding="utf-8"))
for line in subproj:
    for name in re.findall(r"\b(\w+)\b", line):
        if name in ("SUBPROJECTS",):
            continue
        if not (ROOT / name).is_dir():
            error(f"[subproject] Makefile references missing dir `{name}/`")

# --------------------------------------------------------------------------
print("=" * 60)
if ERRORS:
    for e in ERRORS:
        print(f"  FAIL  {e}")
    print(f"=" * 60)
    print(f"{len(ERRORS)} issue(s) found.")
    sys.exit(1)
print("  OK    every check passed.")
print("=" * 60)
sys.exit(0)