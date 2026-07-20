#!/usr/bin/env python3
"""
scripts/extract_strings.py

Heuristic extractor to find likely user-visible string literals in Swift and storyboard files.
Produces a JSON file with discovered strings; developers can review and convert them to NSLocalizedString keys.

Usage:
  python3 scripts/extract_strings.py > strings_to_localize.json

Notes:
 - This is a best-effort tool. Manual review is required to avoid false positives (URLs, log messages, format strings, etc.).
 - After reviewing, replace occurrences in code with NSLocalizedString("<key>", comment: "") and add translations to Localizable.strings.
"""

import re
import os
import sys
import json

ROOT = os.path.join(os.path.dirname(__file__), '..')
EXTS = ['.swift', '.storyboard', '.xib']

# Regex to find string literals in Swift/storyboard: "..."
string_re = re.compile(r'@?"([^"\\]*(?:\\.[^"\\]*)*)"')

# Heuristics to exclude unlikely user-facing strings
exclude_patterns = [
    re.compile(r'^https?://'),
    re.compile(r'^[A-Za-z0-9_\-]+\.[A-Za-z]{2,}'), # filenames, domains
    re.compile(r'^[0-9:\.]+$'), # durations, timestamps
    re.compile(r'%[0-9\$]*[@dfsu]'), # printf-like format
    re.compile(r'^[0-9]+$'),
]

results = {}

for dirpath, dirnames, filenames in os.walk(ROOT):
    # skip .git and build directories
    if '.git' in dirpath or 'Carthage' in dirpath or 'Pods' in dirpath:
        continue
    for fn in filenames:
        path = os.path.join(dirpath, fn)
        if not any(fn.endswith(ext) for ext in EXTS):
            continue
        try:
            with open(path, 'r', encoding='utf-8') as f:
                data = f.read()
        except Exception:
            continue
        for m in string_re.finditer(data):
            s = m.group(1)
            s_unescaped = s.encode('utf-8').decode('unicode_escape')
            s_trim = s_unescaped.strip()
            if not s_trim:
                continue
            # skip strings that are likely code/URLs/identifiers
            if any(p.search(s_trim) for p in exclude_patterns):
                continue
            # skip very short single-letter tokens except common ones
            if len(s_trim) == 1 and s_trim not in ['?', '!', '•', '●']:
                continue
            # record the occurrence
            entry = results.setdefault(s_trim, [])
            entry.append(path)

# Output as JSON: {string: [files...]}
print(json.dumps(results, ensure_ascii=False, indent=2))
