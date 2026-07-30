#!/usr/bin/env python3
"""Validate every SF Symbol string literal in the LYFESTYL sources against the
system CoreGlyphs name database, and report the minimum iOS release each needs.

Usage: python3 check_symbols.py [root]
"""
import json, os, re, sys, subprocess

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/Users/armaanjhajj/LYFESTYLE/LYFESTYLE"
HERE = os.path.dirname(os.path.abspath(__file__))
PLIST = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"

raw = subprocess.run(["plutil", "-convert", "json", "-o", "-", PLIST],
                     capture_output=True, text=True, check=True).stdout
db = json.loads(raw)
symbols = db["symbols"]          # name -> release token e.g. "2020.1"
year_to_release = db["year_to_release"]  # token -> {iOS: "14.0", ...}

# Symbol names appear as `systemName: "..."`, `Image(systemName: "...")`, or as a
# `symbolName` computed property returning a literal. Collect every string literal
# that plausibly names a symbol, then only complain about ones used as symbols.
SYSTEM_NAME = re.compile(r'systemName:\s*"([^"]+)"')
# `case .foo: "bar.baz"` inside a symbolName property, plus `symbolName = "x"`.
BARE_IN_SYMBOL_PROP = re.compile(r'"([a-z0-9][a-zA-Z0-9._]*)"')

def symbol_literals(path, text):
    """Yield (name, line_no) for each string used as an SF Symbol name."""
    lines = text.splitlines()
    in_symbol_prop = False
    brace_depth_at_entry = 0
    depth = 0
    for i, line in enumerate(lines, 1):
        for m in SYSTEM_NAME.finditer(line):
            yield m.group(1), i
        # Track a `var symbolName: String {` / `func symbolName(...) -> String {`
        # block so bare literals inside it are treated as symbol names.
        if not in_symbol_prop and re.search(r'(var|func)\s+\w*[sS]ymbol\w*\b', line):
            in_symbol_prop = True
            brace_depth_at_entry = depth
        opens = line.count("{")
        closes = line.count("}")
        if in_symbol_prop and "systemName:" not in line:
            for m in BARE_IN_SYMBOL_PROP.finditer(line):
                name = m.group(1)
                if "." in name or name in symbols:
                    yield name, i
        depth += opens - closes
        if in_symbol_prop and depth <= brace_depth_at_entry and (closes > 0):
            in_symbol_prop = False
    return

bad = []
oldest = {}
seen = set()
for dirpath, _dirs, files in os.walk(ROOT):
    for fn in files:
        if not fn.endswith(".swift"):
            continue
        p = os.path.join(dirpath, fn)
        text = open(p, encoding="utf-8").read()
        for name, line in symbol_literals(p, text):
            if name in seen and name in symbols:
                continue
            seen.add(name)
            if name not in symbols:
                bad.append((os.path.relpath(p, ROOT), line, name))
            else:
                tok = symbols[name]
                ios = year_to_release.get(tok, {}).get("iOS", "?")
                oldest.setdefault(ios, []).append(name)

if bad:
    print(f"INVALID SF SYMBOLS ({len(bad)}):")
    for path, line, name in bad:
        print(f"  {path}:{line}  {name!r}")
else:
    print("All SF Symbol names valid.")

def key(v):
    try:
        return tuple(int(x) for x in v.split("."))
    except Exception:
        return (999,)

newest = sorted(oldest.keys(), key=key, reverse=True)[:4]
print("\nNewest iOS requirements among symbols used:")
for ios in newest:
    print(f"  iOS {ios}: {', '.join(sorted(oldest[ios])[:14])}")
print(f"\n{len(seen)} distinct symbol names checked.")
sys.exit(1 if bad else 0)
