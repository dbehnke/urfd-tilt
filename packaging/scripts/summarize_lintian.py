#!/usr/bin/env python3
"""
Summarize lintian output files under artifacts/ and produce a compact report.

Usage: python3 packaging/scripts/summarize_lintian.py
Writes artifacts/lintian-summary.txt
"""

import glob
import re
from collections import Counter

OUT = "artifacts/lintian-summary.txt"


def parse_file(path):
    errors = []
    warnings = []
    notes = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            l = line.strip()
            # Lintian lines often include severity tags; simple heuristics
            if re.search(r"\berror\b", l, re.I):
                errors.append(l)
            elif re.search(r"\bwarning\b", l, re.I):
                warnings.append(l)
            elif re.search(r"\binfo\b|\bnotes?\b|\bexperimental\b", l, re.I):
                notes.append(l)
    return errors, warnings, notes


def main():
    files = sorted(
        glob.glob("artifacts/*lintian*.txt")
        + glob.glob("artifacts/*lintian*.log")
        + glob.glob("artifacts/lintian-*.txt")
    )
    if not files:
        print("No lintian artifact files found under artifacts/")
        return 1

    total = Counter()
    issue_counts = Counter()
    details = []

    for f in files:
        e, w, n = parse_file(f)
        total["errors"] += len(e)
        total["warnings"] += len(w)
        total["notes"] += len(n)
        for line in e + w + n:
            # collapse variable parts to identify common issues
            key = re.sub(r"\s+\S+\.deb", " <deb>", line)
            key = re.sub(r"\s+\d+\:\d+\:\d+", " <time>", key)
            issue_counts[key] += 1
        details.append((f, len(e), len(w), len(n)))

    with open(OUT, "w", encoding="utf-8") as out:
        out.write("Lintian summary\n")
        out.write("================\n\n")
        out.write(f"Files analyzed: {len(files)}\n")
        out.write(f"Total errors: {total['errors']}\n")
        out.write(f"Total warnings: {total['warnings']}\n")
        out.write(f"Total notes: {total['notes']}\n\n")
        out.write("Per-file counts:\n")
        for f, e, w, n in details:
            out.write(f" - {f}: errors={e} warnings={w} notes={n}\n")
        out.write("\nTop issue samples:\n")
        for k, c in issue_counts.most_common(20):
            out.write(f"[{c}] {k}\n")

    print(f"Wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
