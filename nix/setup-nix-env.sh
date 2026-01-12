#!/bin/bash
# setup-nix-env.sh
# Purpose: One-command setup for the Nix-based R/Python environment
# Run this on every container restart to restore the environment
#
# Usage: ./setup-nix-env.sh
#
# What this does:
# 1. Installs nix-portable to /tmp (if not present)
# 2. Builds/enters the flake-defined development environment
# 3. Environment includes R, Python, Quarto, and all packages

set -euo pipefail

echo "========== CHRWD Nix Environment Setup =========="
date
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WORK_DIR="${WORK_DIR:-$SCRIPT_DIR}"
cd "$WORK_DIR"

NIX_PORTABLE_DIR="/tmp/nix-portable"
NIX_PORTABLE_BIN="$NIX_PORTABLE_DIR/nix-portable"
export NP_LOCATION="/tmp/nix-portable-home"

# ============================================================
# Part 1: Bootstrap nix-portable
# ============================================================
echo "=== Part 1: Bootstrapping nix-portable ==="

mkdir -p "$NIX_PORTABLE_DIR"
mkdir -p "$NP_LOCATION"

if [[ ! -x "$NIX_PORTABLE_BIN" ]]; then
    echo "Downloading nix-portable..."
    curl -L -o "$NIX_PORTABLE_BIN" \
        "https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m)"
    chmod +x "$NIX_PORTABLE_BIN"
    echo "✓ nix-portable installed"
else
    echo "✓ nix-portable already present"
fi

# Verify nix works
echo "Testing nix..."
"$NIX_PORTABLE_BIN" nix --version
echo ""

# ============================================================
# Part 2: Ensure flake.nix exists
# ============================================================
echo "=== Part 2: Checking flake.nix ==="

if [[ ! -f "$WORK_DIR/flake.nix" ]]; then
    echo "ERROR: flake.nix not found in $WORK_DIR"
    echo "Copy flake.nix to your working directory first."
    exit 1
fi
echo "✓ flake.nix found"
echo ""

# ============================================================
# Part 3: Build and enter the environment
# ============================================================
echo "=== Part 3: Building Nix environment ==="
echo "This may take several minutes on first run..."
echo "(Subsequent runs use cached builds)"
echo ""

# Create a script that will be sourced to enter the environment
# nix-portable doesn't support 'nix develop' interactively well,
# so we use 'nix print-dev-env' to get the environment variables

ENV_SCRIPT="/tmp/nix-env-vars.sh"

echo "Generating environment..."
"$NIX_PORTABLE_BIN" nix print-dev-env \
    --extra-experimental-features 'nix-command flakes' \
    "$WORK_DIR" > "$ENV_SCRIPT" 2>&1 || {
    echo "ERROR: Failed to build environment. Check flake.nix for errors."
    echo "Output:"
    cat "$ENV_SCRIPT"
    exit 1
}

echo "✓ Environment built successfully"
echo ""

# ============================================================
# Part 4: Create activation helper
# ============================================================
echo "=== Part 4: Creating activation helper ==="

ACTIVATE_SCRIPT="$WORK_DIR/activate-nix-env.sh"
cat > "$ACTIVATE_SCRIPT" << 'ACTIVATE'
#!/bin/bash
# Source this file to activate the Nix environment in your current shell:
#   source ./activate-nix-env.sh

export NP_LOCATION="/tmp/nix-portable-home"

if [[ -f "/tmp/nix-env-vars.sh" ]]; then
    source "/tmp/nix-env-vars.sh"
    echo "Nix environment activated."
    echo "R version: $(R --version 2>/dev/null | head -n1 || echo 'not available')"
    echo "Python version: $(python --version 2>/dev/null || echo 'not available')"
    echo "Quarto version: $(quarto --version 2>/dev/null || echo 'not available')"
else
    echo "ERROR: Environment not built. Run ./setup-nix-env.sh first."
    return 1
fi
ACTIVATE

chmod +x "$ACTIVATE_SCRIPT"
echo "✓ Created $ACTIVATE_SCRIPT"
echo ""

# ============================================================
# Part 5: Instructions
# ============================================================
echo "=========================================="
echo "✓ Setup Complete!"
echo "=========================================="
echo ""
echo "To activate the environment in your current shell:"
echo ""
echo "  source ./activate-nix-env.sh"
echo ""
echo "Or to enter an interactive shell with the environment:"
echo ""
echo "  $NIX_PORTABLE_BIN nix develop --extra-experimental-features 'nix-command flakes'"
echo ""
echo "Add to .bashrc for automatic activation:"
echo ""
echo "  echo 'source $WORK_DIR/activate-nix-env.sh' >> ~/.bashrc"
echo ""
echo "=========================================="
