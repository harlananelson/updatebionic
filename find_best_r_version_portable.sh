#!/bin/sh
set -euo pipefail

# ================================
# Script: find_best_r_version_portable.sh
# Purpose: Determine the most recent R version that supports all packages in requirements-R.txt
# Preconditions:
#   - requirements-R.txt contains one package name per line, prefixed with "r-"
#   - conda_search_log.txt contains full conda search output for each package
# ================================

REQ_FILE="requirements-R.txt"
SEARCH_LOG="conda_search_log.txt"

# Extract required R packages (ignore commented lines)
REQ_PACKAGES=$(grep -v '^#' "$REQ_FILE" | sed 's/^[[:space:]]*//' | sort -u)

# Create a temp file to collect R versions per package
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

for pkg in $REQ_PACKAGES; do
    grep -i "$pkg" "$SEARCH_LOG" | grep -oE 'r[0-9]{2}' | sort -u > "$TMP_DIR/$pkg"
done

# Find intersection of all version files
cp "$TMP_DIR/$(ls "$TMP_DIR" | head -n1)" "$TMP_DIR/intersection"

for pkg in $REQ_PACKAGES; do
    comm -12 "$TMP_DIR/intersection" "$TMP_DIR/$pkg" > "$TMP_DIR/tmp" && mv "$TMP_DIR/tmp" "$TMP_DIR/intersection"
done

# Output the most recent compatible R version
if [ -s "$TMP_DIR/intersection" ]; then
    best_version=$(tail -n1 "$TMP_DIR/intersection")
    echo "✅ Most recent compatible R version: $best_version"
else
    echo "❌ No common R version found that supports all packages."
    exit 1
fi
