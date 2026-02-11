#!/usr/bin/env python3
"""
Check 'src:' entries in packaging/nfpm/*.yaml for existence for amd64 and arm64.
Print a compact report suitable for CI or manual inspection.
"""

import glob
import os
import re

PKG_VERSION = os.environ.get("PKG_VERSION", "671f9-dirty")
ARCHS = ["amd64", "arm64"]


def extract_srcs(path):
    srcs = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\s*-\s*src:\s*(.*)$", line)
            if m:
                val = m.group(1).strip()
                # remove surrounding quotes if present
                if (val.startswith("'") and val.endswith("'")) or (
                    val.startswith('"') and val.endswith('"')
                ):
                    val = val[1:-1]
                srcs.append(val)
    return srcs


def main():
    base = os.getcwd()
    manifests = sorted(glob.glob("packaging/nfpm/*.yaml"))
    if not manifests:
        print("No nfpm manifests found in packaging/nfpm/")
        return 0
    missing = {}
    print("Checking", len(manifests), "nfpm manifests")
    for m in manifests:
        print("\nManifest:", m)
        srcs = extract_srcs(m)
        if not srcs:
            print("  (no src entries)")
            continue
        for s in srcs:
            for arch in ARCHS:
                path = s.replace("${ARCH}", arch).replace("${PKG_VERSION}", PKG_VERSION)
                abs_path = os.path.join(base, path)
                ok = os.path.exists(abs_path)
                status = "OK" if ok else "MISSING"
                print(f"  [{status}] ({arch}) {s} -> {path}")
                if not ok:
                    missing.setdefault(m, []).append((arch, s, path))

    print("\nSummary:")
    if not missing:
        print("  All referenced src files exist for amd64 and arm64")
        return 0
    print("  Missing files detected in the following manifests:")
    for m, items in missing.items():
        print(" -", m)
        for arch, s, path in items:
            print(f"    * ({arch}) {s} -> {path}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
