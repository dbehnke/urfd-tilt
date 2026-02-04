#!/bin/bash
git describe --tags --always --dirty --abbrev=5 --match "v*" 2>/dev/null \
  | sed 's/-g\([0-9a-f]\)/-\1/' || echo "v0.0.0-dev"
