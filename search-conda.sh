#!/bin/bash

# Script to search for R packages availability in conda-forge
# Usage: bash search_r_packages.sh

echo "=================================================="
echo "Searching for R packages in conda-forge channel"
echo "=================================================="
echo

# List of R packages to search for
packages=(
    "r-matrix"
    "r-mass"
    "r-tidyverse"
    "r-data.table"
    "r-tidymodels"
    "r-targets"
    "r-tarchetypes"
    "r-gtsummary"
    "r-ggpubr"
    "r-pacman"
    "r-pak"
    "r-renv"
    "r-here"
    "r-janitor"
    "r-curl"
    "r-survminer"
    "r-nanoparquet"
    "r-sparklyr"
    "r-tidycensus"
    "r-remotes"
    "r-ranger"
    "r-ggally"
    "r-xgboost"
    "r-pdp"
    "r-contrast"
    "r-cardx"
    "r-estimability"
    "r-mvtnorm"
    "r-numderiv"
    "r-emmeans"
    "r-pillar"
    "r-pkgconfig"
    "r-mgcv"
)

# Commented out packages (as noted in original list)
commented_packages=(
    "r-visnetwork"
    "r-reticulate" 
    "r-rhdfs"
)

# Create output files
available_packages="available_packages.txt"
unavailable_packages="unavailable_packages.txt"
search_log="conda_search_log.txt"

# Clear previous results
> "$available_packages"
> "$unavailable_packages"
> "$search_log"

echo "Starting conda search for R packages..."
echo "Results will be saved to:"
echo "  - Available packages: $available_packages"
echo "  - Unavailable packages: $unavailable_packages"
echo "  - Full search log: $search_log"
echo

# Function to search for a package
search_package() {
    local package=$1
    echo "Searching for: $package"
    
    # Search in conda-forge channel
    search_result=$(conda search -c conda-forge "$package" 2>&1)
    
    # Log the full output
    echo "=== Search for $package ===" >> "$search_log"
    echo "$search_result" >> "$search_log"
    echo "" >> "$search_log"
    
    # Check if package was found
    if echo "$search_result" | grep -q "No match found"; then
        echo "  ❌ NOT FOUND"
        echo "$package" >> "$unavailable_packages"
    elif echo "$search_result" | grep -q "$package"; then
        echo "  ✅ AVAILABLE"
        echo "$package" >> "$available_packages"
        # Extract latest version info
        latest_version=$(echo "$search_result" | grep "$package" | tail -1 | awk '{print $2}')
        echo "$package (latest: $latest_version)" >> "$available_packages"
    else
        echo "  ⚠️  UNCLEAR RESULT"
        echo "$package (unclear)" >> "$unavailable_packages"
    fi
    
    # Small delay to avoid overwhelming conda
    sleep 0.5
}

# Search for all packages
for package in "${packages[@]}"; do
    search_package "$package"
done

echo
echo "=== SUMMARY ==="
echo
echo "Available packages ($(wc -l < "$available_packages" | tr -d ' ')):"
echo "----------------------------------------"
if [[ -s "$available_packages" ]]; then
    cat "$available_packages"
else
    echo "None found"
fi

echo
echo "Unavailable packages ($(wc -l < "$unavailable_packages" | tr -d ' ')):"
echo "----------------------------------------"
if [[ -s "$unavailable_packages" ]]; then
    cat "$unavailable_packages"
else
    echo "All packages available!"
fi

echo
echo "=== COMMENTED OUT PACKAGES ==="
echo "The following packages were commented out in the original list:"
for package in "${commented_packages[@]}"; do
    echo "  - $package"
done

echo
echo "=== INSTALLATION COMMAND ==="
echo "To install all available packages at once:"
echo
if [[ -s "$available_packages" ]]; then
    echo -n "conda install -c conda-forge "
    # Extract just package names (remove version info)
    grep -v "^$" "$available_packages" | sed 's/ (latest:.*)//' | tr '\n' ' '
    echo
    echo
    echo "Or using mamba (faster):"
    echo -n "mamba install -c conda-forge "
    grep -v "^$" "$available_packages" | sed 's/ (latest:.*)//' | tr '\n' ' '
    echo
fi

echo
echo "=== ALTERNATIVE SEARCH ==="
echo "You can also search individual packages manually:"
echo "  conda search -c conda-forge PACKAGE_NAME"
echo "  mamba search -c conda-forge PACKAGE_NAME"
echo
echo "For packages not available via conda, install in R:"
echo '  R -e "install.packages(c(\"package1\", \"package2\"))"'
echo
echo "Search completed! Check $search_log for detailed results."