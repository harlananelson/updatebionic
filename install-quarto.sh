#!/bin/bash
# install-quarto.sh
#
# Standalone Quarto installer — extracted from setup-system.sh Part 2.
# Run this directly to diagnose or repair a missing quarto installation.
#
# Usage:
#   bash install-quarto.sh
#   QUARTO_TAG=v1.3.450 bash install-quarto.sh   # force a specific version

set -eo pipefail

QUARTO_FALLBACK_TAG="v1.6.43"

# ========== Retry Helper ==========
retry_cmd() {
    local max_attempts=$1
    local delay=$2
    local desc=$3
    shift 3
    local attempt=1
    while true; do
        echo "[$desc] Attempt $attempt of $max_attempts..."
        if "$@"; then
            echo "[$desc] Succeeded on attempt $attempt."
            return 0
        fi
        if (( attempt >= max_attempts )); then
            echo "[$desc] FAILED after $max_attempts attempts."
            return 1
        fi
        echo "[$desc] Failed. Retrying in ${delay}s..."
        sleep "$delay"
        ((attempt++))
    done
}

echo "========== Quarto Installer / Diagnostics =========="
date

# ========== Diagnostics ==========
echo ""
echo "--- System info ---"
echo "GLIBC version:"
ldd --version 2>/dev/null | head -1 || echo "  (ldd not available)"
echo "OS release:"
cat /etc/os-release 2>/dev/null | grep -E '^(NAME|VERSION)=' || true
echo "Current PATH: $PATH"
echo "quarto currently on PATH: $(command -v quarto 2>/dev/null || echo 'not found')"
echo "/usr/local/bin contents (quarto-related):"
ls -la /usr/local/bin/quarto* 2>/dev/null || echo "  (none)"
echo "/opt/quarto contents:"
ls /opt/quarto/ 2>/dev/null || echo "  (none)"

# ========== Already installed? ==========
echo ""
if command -v quarto >/dev/null 2>&1 && quarto --version >/dev/null 2>&1; then
    echo "Quarto already installed and working: $(quarto --version) at $(command -v quarto)"
    echo "Nothing to do."
    exit 0
fi

# ========== Determine version ==========
echo ""
echo "--- Determining Quarto version to install ---"

if [[ -n "${QUARTO_TAG:-}" ]]; then
    LATEST_TAG="$QUARTO_TAG"
    echo "Using QUARTO_TAG override: $LATEST_TAG"
else
    echo "Fetching latest release tag from GitHub API..."
    LATEST_TAG=$(curl -fsS https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest 2>/dev/null \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [[ -z "$LATEST_TAG" ]]; then
        echo "WARNING: GitHub API lookup failed. Falling back to $QUARTO_FALLBACK_TAG."
        LATEST_TAG="$QUARTO_FALLBACK_TAG"
    else
        echo "Latest release: $LATEST_TAG"
    fi
fi

QUARTO_VERSION=${LATEST_TAG#v}
RELEASE_URL="https://github.com/quarto-dev/quarto-cli/releases/download/${LATEST_TAG}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
QUARTO_TARBALL="/tmp/quarto-${QUARTO_VERSION}.tar.gz"

echo "Version: $QUARTO_VERSION"
echo "URL: $RELEASE_URL"

# ========== Download ==========
echo ""
echo "--- Downloading ---"
retry_cmd 3 15 "quarto download" \
    curl -fSL --connect-timeout 30 --max-time 600 -o "$QUARTO_TARBALL" "$RELEASE_URL"

TARBALL_SIZE=$(stat -c '%s' "$QUARTO_TARBALL" 2>/dev/null || echo 0)
echo "Downloaded: ${TARBALL_SIZE} bytes"

# ========== Extract ==========
echo ""
echo "--- Extracting ---"
sudo mkdir -p "/opt/quarto/${QUARTO_VERSION}"
sudo tar -xzf "$QUARTO_TARBALL" -C "/opt/quarto/${QUARTO_VERSION}" --strip-components=1
rm -f "$QUARTO_TARBALL"
sudo ln -sf "/opt/quarto/${QUARTO_VERSION}/bin/quarto" "/usr/local/bin/quarto"
echo "Extracted to /opt/quarto/${QUARTO_VERSION}, symlinked to /usr/local/bin/quarto"

# ========== Verify ==========
echo ""
echo "--- Verifying ---"
echo "Attempting: /usr/local/bin/quarto --version"
if /usr/local/bin/quarto --version 2>&1; then
    echo ""
    echo "SUCCESS: Quarto $(/usr/local/bin/quarto --version 2>/dev/null) is installed and working."
else
    echo ""
    echo "ERROR: quarto binary does not run. Capturing error output:"
    /usr/local/bin/quarto --version 2>&1 || true
    echo ""
    echo "This is usually a GLIBC version mismatch."
    echo "Try an older release with:  QUARTO_TAG=v1.3.450 bash install-quarto.sh"
    exit 1
fi

# ========== Symlink into r_env ==========
echo ""
echo "--- Linking into r_env (if present) ---"
for renv in /tmp/r_env-*; do
    [ -x "$renv/bin/python" ] || continue
    ln -sf /usr/local/bin/quarto "$renv/bin/quarto"
    echo "  Linked quarto into $renv/bin/quarto"
done

echo ""
echo "Done."
