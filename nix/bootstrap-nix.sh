#!/bin/bash
# bootstrap-nix.sh
# Purpose: Install nix-portable to /tmp for ephemeral, fast Nix usage on Ubuntu 18.04
# This must be run on every container restart since /tmp is not persistent.
#
# nix-portable bundles its own runtime, avoiding GLIBC 2.27 compatibility issues.

set -euo pipefail

echo "========== Nix Portable Bootstrap for Ubuntu 18.04 =========="
date

NIX_PORTABLE_DIR="/tmp/nix-portable"
NIX_PORTABLE_BIN="$NIX_PORTABLE_DIR/nix-portable"
WORK_DIR="${WORK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"

# Create directory structure
mkdir -p "$NIX_PORTABLE_DIR"
mkdir -p "/tmp/nix"  # nix-portable will use this for the store

# Download nix-portable if not present
if [[ ! -x "$NIX_PORTABLE_BIN" ]]; then
    echo "Downloading nix-portable..."
    curl -L -o "$NIX_PORTABLE_BIN" \
        "https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m)"
    chmod +x "$NIX_PORTABLE_BIN"
    echo "nix-portable installed to $NIX_PORTABLE_BIN"
else
    echo "nix-portable already present at $NIX_PORTABLE_BIN"
fi

# Configure nix-portable environment
# NP_LOCATION: where nix-portable stores its runtime and nix store
export NP_LOCATION="/tmp/nix-portable-home"
mkdir -p "$NP_LOCATION"

# NP_RUNTIME: use bwrap (bubblewrap) if available, otherwise proot
# proot works without root but is slower; bwrap is faster but may need privileges
if command -v bwrap &>/dev/null; then
    export NP_RUNTIME="bwrap"
    echo "Using bwrap runtime (faster)"
else
    export NP_RUNTIME="proot"
    echo "Using proot runtime (bwrap not available)"
fi

# Test nix-portable
echo "Testing nix-portable..."
"$NIX_PORTABLE_BIN" nix --version

# Create convenience wrapper script
cat > "$NIX_PORTABLE_DIR/nix" << 'WRAPPER'
#!/bin/bash
# Wrapper to invoke nix via nix-portable with correct environment
export NP_LOCATION="/tmp/nix-portable-home"
exec /tmp/nix-portable/nix-portable nix "$@"
WRAPPER
chmod +x "$NIX_PORTABLE_DIR/nix"

# Create wrapper for nix develop
cat > "$NIX_PORTABLE_DIR/nix-develop" << 'WRAPPER'
#!/bin/bash
# Wrapper for 'nix develop' command
export NP_LOCATION="/tmp/nix-portable-home"
exec /tmp/nix-portable/nix-portable nix develop "$@"
WRAPPER
chmod +x "$NIX_PORTABLE_DIR/nix-develop"

# Add to PATH for current session
export PATH="$NIX_PORTABLE_DIR:$PATH"

echo ""
echo "========== Nix Portable Bootstrap Complete =========="
echo ""
echo "Add to your current session:"
echo "  export NP_LOCATION=\"/tmp/nix-portable-home\""
echo "  export PATH=\"/tmp/nix-portable:\$PATH\""
echo ""
echo "To enter the development environment:"
echo "  cd $WORK_DIR"
echo "  nix-develop --extra-experimental-features 'nix-command flakes'"
echo ""
echo "Or add to .bashrc for persistence across terminal sessions:"
echo "  echo 'export NP_LOCATION=\"/tmp/nix-portable-home\"' >> ~/.bashrc"
echo "  echo 'export PATH=\"/tmp/nix-portable:\$PATH\"' >> ~/.bashrc"
