#!/bin/bash
set -e

#!/bin/bash
set -e
#
# ensure-repos.sh (reworked for submodules)
# Initializes and updates git submodules for this project (paths under urfd-tilt/src/).
#

echo "Syncing .gitmodules and updating submodules (repo root)..."
git submodule sync --recursive
git submodule update --init --recursive
echo "Submodules are initialized/updated under urfd-tilt/src/."

exit 0
