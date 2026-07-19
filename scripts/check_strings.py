#!/usr/bin/env python3
"""Validate translation files against the English source of truth.

For every `YTLite/xx.lproj/Localizable.strings` (xx != en):
  - unknown keys (not present in en)          -> ERROR
  - format-placeholder mismatch vs en         -> ERROR
  - duplicate keys within one file            -> ERROR
  - missing keys (present in en, absent here) -> warning only
    (.strings falls back to English at runtime, partial translations ship)

Exit code 1 on any error. Run: python3 Scripts/check_strings.py
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "YTLite")
PAIR_RE = re.compile(r'^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?[@dDuUxXoOfeEgGcCsSaAF]|%%")


def parse(path):
    pairs, dupes = {}, []
    for line in open(path, encoding="utf-8"):
        match = PAIR_RE.match(line.strip())
        if not match:
            continue
        key, value = match.group(1), match.group(2)
        if key in pairs:
            dupes.append(key)
        pairs[key] = value
    return pairs, dupes


def placeholders(value):
    return sorted(p for p in PLACEHOLDER_RE.findall(value) if p != "%%")


def main():
    en, en_dupes = parse(os.path.join(ROOT, "en.lproj", "Localizable.strings"))
    errors = [f"en.lproj: duplicate key '{k}'" for k in en_dupes]
    warnings = []
    for path in sorted(glob.glob(os.path.join(ROOT, "*.lproj", "Localizable.strings"))):
        lang = os.path.basename(os.path.dirname(path))
        if lang == "en.lproj":
            continue
        loc, dupes = parse(path)
        errors += [f"{lang}: duplicate key '{k}'" for k in dupes]
        for key, value in loc.items():
            if key not in en:
                errors.append(f"{lang}: unknown key '{key}'")
            elif placeholders(value) != placeholders(en[key]):
                errors.append(
                    f"{lang}: placeholder mismatch in '{key}': "
                    f"{placeholders(value)} vs en {placeholders(en[key])}"
                )
        missing = sorted(set(en) - set(loc))
        if missing:
            warnings.append(f"{lang}: {len(missing)} missing keys (fall back to English)")
        print(f"{lang}: {len(loc)}/{len(en)} keys")
    for warning in warnings:
        print(f"warning: {warning}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
