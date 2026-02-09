#!/usr/bin/env python3
"""
Create placeholder files for missing 'src' entries referenced by packaging/nfpm/*.yaml.
This helps iterative packaging runs when full builds are not possible on the host.

Behavior:
 - For each '- src: <path>' entry, replace ${ARCH} with amd64 and arm64 and check
   whether the path exists. If missing, create a minimal placeholder file or
   directory as appropriate.
 - If the src contains a glob (*) create a representative file matching the
   glob (first pattern component).
 - Libraries (.a) and headers (.h) get minimal empty files. Binaries get a
   small shell script marked executable. Directories are created.

Run from repository root.
"""

import glob
import os
import re
import stat

ARCHS = ["amd64", "arm64"]
NFPM_DIR = os.path.join("packaging", "nfpm")


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def touch(path, mode=0o644, executable=False, content=None):
    ensure_dir(os.path.dirname(path))
    with open(path, "w", encoding="utf-8") as fh:
        if content:
            fh.write(content)
        else:
            fh.write("// placeholder\n")
    os.chmod(path, mode | (0o111 if executable else 0))


def write_gz(path, content_bytes: bytes):
    """Write a gzip-compressed file alongside the given path (path should include .gz)."""
    import gzip

    ensure_dir(os.path.dirname(path))
    with gzip.open(path, "wb") as fh:
        fh.write(content_bytes)


def make_placeholder_for_path(path):
    # If path contains globbing, create a representative file
    if "*" in path:
        # replace glob with a single file name
        p = re.sub(r"\*+", "placeholder", path)
        path = p

    dirname = os.path.dirname(path)
    ensure_dir(dirname)

    # choose placeholder type by extension
    _, ext = os.path.splitext(path)
    if ext in (".a",):
        # static library placeholder
        touch(path, mode=0o644, executable=False, content="/\n")
    elif ext in (".h", ".hpp"):
        touch(path, mode=0o644, executable=False, content="/* placeholder header */\n")
    else:
        # assume binary
        # long-running placeholder for service binaries (names like 'urfd' or 'tcd')
        name = os.path.basename(path)
        if name in ("urfd", "tcd", "allstar-nexus", "urfd-dashboard"):
            content = (
                "#!/bin/sh\n# placeholder long-running binary\nexec tail -f /dev/null\n"
            )
            touch(path, mode=0o755, executable=True, content=content)
        else:
            # simple executable that prints version
            content = "#!/bin/sh\necho '%s placeholder'\nexit 0\n" % name
            touch(path, mode=0o755, executable=True, content=content)

    # If packaging expects a gzipped changelog (changelog.Debian.gz), create it
    if path.endswith("changelog.Debian"):
        gzpath = path + ".gz"
        if not os.path.exists(gzpath):
            write_gz(
                gzpath,
                (
                    content.encode("utf-8")
                    if content
                    else b"Initial placeholder changelog\n"
                ),
            )


def main():
    files = glob.glob(os.path.join(NFPM_DIR, "*.yaml"))
    if not files:
        print("No nfpm manifest files found")
        return

    missing = []
    for f in files:
        with open(f, "r", encoding="utf-8") as fh:
            for i, line in enumerate(fh, 1):
                m = re.match(r"\s*-\s*src:\s*(.*)$", line)
                if not m:
                    continue
                src = m.group(1).strip()
                for arch in ARCHS:
                    path = src.replace("${ARCH}", arch)
                    # collapse any accidental duplicate slashes
                    path = os.path.normpath(path)
                    if not os.path.exists(path):
                        print(f"Missing: {path} (from {f}:{i})")
                        make_placeholder_for_path(path)
                        print(f"  -> created placeholder: {path}")
                        # also ensure .gz variants exist where expected (changelog.Debian.gz)
                        if path.endswith("changelog.Debian"):
                            gz = path + ".gz"
                            if not os.path.exists(gz):
                                write_gz(gz, b"Initial placeholder changelog\n")
                                print(f"  -> created gzip changelog: {gz}")
                                missing.append(gz)
                        missing.append(path)

    print(f"Created {len(missing)} placeholders (if any).")


if __name__ == "__main__":
    main()
