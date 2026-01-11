#!/bin/bash
set -e

# Parent directory where repos are expected
PARENT_DIR=..

# Function to ensure a repo exists
ensure_repo() {
    REPO_NAME=$1
    REPO_URL=$2

    if [ ! -d "$PARENT_DIR/$REPO_NAME" ]; then
        echo "Cloning $REPO_NAME..."
        git clone "$REPO_URL" "$PARENT_DIR/$REPO_NAME"
    else
        echo "$REPO_NAME already exists."
    fi
}

echo "Ensuring repositories..."

ensure_repo "urfd" "https://github.com/dbehnke/urfd.git"
ensure_repo "tcd" "https://github.com/dbehnke/tcd.git"
ensure_repo "urfd-nng-dashboard" "https://github.com/dbehnke/urfd-nng-dashboard.git"
ensure_repo "allstar-nexus" "https://github.com/dbehnke/allstar-nexus.git"
ensure_repo "imbe_vocoder" "https://github.com/nostar/imbe_vocoder.git"

echo "All required repositories checked."
