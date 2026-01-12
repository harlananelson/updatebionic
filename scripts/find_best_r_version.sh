#!/usr/bin/env bash
set -euo pipefail

# ================================
# Script: find_best_r_version.sh
# Purpose: Determine the most recent R version that supports all packages in requirements-R.txt
# Preconditions:
#   - requirements-R.txt contains one package name per line, prefixed with "r-"
#   - conda_search_log.txt contains full conda search output for each package
# ================================

REQ_FILE="requirements-R.txt"
SEARCH_LOG="conda_search_log.txt"

# Extract required R packages (ignore commented lines)
REQ_PACKAGES=$(grep -v '^#' "$REQ_FILE" | sed 's/^[[:space:]]*//' | sort -u)

# Extract all R versions per package from the search log
declare -A r_versions_by_package

for pkg in $REQ_PACKAGES; do
    # Find all lines for the package and extract R version (e.g., r42, r43, r44)
    versions=$(grep -i "$pkg" "$SEARCH_LOG" | grep -oE 'r[0-9]{2}' | sort -u)
    if [[ -z "$versions" ]]; then
        echo "Package $pkg has no matching R versions in search log."
        exit 1
    fi
    r_versions_by_package["$pkg"]="$versions"
done

# Find intersection of R versions across all packages
common_versions=$(printf "%s\n" "${r_versions_by_package[@]}" | tr ' ' '\n' | sort | uniq -c | awk -v total=$(echo "$REQ_PACKAGES" | wc -l) '$1 == total {print $2}' | sort -V)

if [[ -z "$common_versions" ]]; then
    echo "No common R version found that supports all packages."
    exit 1
fi

# Output the most recent compatible R version
best_version=$(echo "$common_versions" | tail -n1)
echo "✅ Most recent compatible R version: $best_version"
