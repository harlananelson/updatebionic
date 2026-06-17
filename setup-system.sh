#!/bin/bash
# setup-system.sh
#
# Shared, machine-wide setup for the LHN container. Installs items that ALL
# users share and that require sudo:
#   1. System library dependencies (GDAL, GEOS, PROJ, compilers, fonts, ssh)
#   2. Quarto CLI (system-wide, /opt/quarto)
#   3. pip packages into the original Docker conda (/opt/conda)
#   4. Miniconda (shared conda driver, /tmp/miniconda)
#
# Per-user environments and Jupyter kernels are created by setup-user.sh,
# which each user runs for themselves.
#
# This script is safe to run repeatedly and by either user:
#   - An flock (LOCKFILE) serialises concurrent runs so two people cannot
#     install system packages / Quarto / Miniconda at the same time.
#   - A daily sentinel (/tmp/.lhn-system-ready) makes a same-day re-run a
#     fast no-op. Use FORCE_SYSTEM_SETUP=1 to override.
#
# Recommended workflow: someone runs this once each morning (or the first
# time a user runs setup-user.sh on a fresh container). setup-user.sh will
# automatically invoke this script if the shared setup has not completed
# for the current day.
#
# Usage:
#   chmod +x setup-system.sh
#   ./setup-system.sh
#   FORCE_SYSTEM_SETUP=1 ./setup-system.sh   # force a full re-run

# Note: not using -u (nounset) because conda activation scripts have unbound vars
set -eo pipefail

# ========== Configuration ==========
OLD_CONDA_PATH="/opt/conda"
MINICONDA_PATH="/tmp/miniconda"          # shared conda driver (wiped on reboot)

# Node-wide sentinel + lockfile (revert of 1b008cf).
#
# This node is SHARED across users: /tmp, /opt and /usr/local are visible to
# everyone in the same container, so setup-system installs machine-wide items
# ONCE and every user's setup-user then consumes them. The earlier per-$USER
# suffix (commit 1b008cf) was added on the assumption that "each user gets
# their own container" — that is not the case here. The per-user suffix meant
# a second user on the same node would not see that the shared setup had
# already completed for the day, causing unnecessary re-execution.
#
# A single node-wide sentinel restores the intended "run once, everyone
# benefits" behaviour. The lockfile is likewise node-wide so concurrent runs
# by different users serialise against each other.
SENTINEL="/tmp/.lhn-system-ready"            # node-wide sentinel
LOCKFILE="/tmp/lhn-setup-system.lock"        # node-wide lock

# Resolve full path to this script (handles both sourced and direct execution)
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$SCRIPT_PATH")"

# ========== Self-Update from GitHub ==========
SELF_UPDATE_REPO="harlananelson/updatebionic"
SELF_UPDATE_BRANCH="main"
SELF_UPDATE_FILE="setup-system.sh"

if [[ "${SKIP_SELF_UPDATE:-}" == "1" ]]; then
    echo "Self-update: skipping (already updated this run)."
else
    echo "Checking GitHub for newer version of $SELF_UPDATE_FILE..."
    REMOTE_SCRIPT=$(curl -sfL "https://raw.githubusercontent.com/${SELF_UPDATE_REPO}/${SELF_UPDATE_BRANCH}/${SELF_UPDATE_FILE}" 2>/dev/null) || true

    if [[ -n "$REMOTE_SCRIPT" ]]; then
        LOCAL_HASH=$(sha256sum "$SCRIPT_PATH" | cut -d' ' -f1)
        REMOTE_HASH=$(echo "$REMOTE_SCRIPT" | sha256sum | cut -d' ' -f1)

        if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
            echo "Newer version found on GitHub. Updating..."
            echo "$REMOTE_SCRIPT" > "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            echo "Updated. Re-executing with new version..."
            export SKIP_SELF_UPDATE=1
            exec "$SCRIPT_PATH" "$@"
        else
            echo "Already running the latest version."
        fi
    else
        echo "Warning: Could not reach GitHub (continuing with current version)."
    fi
fi

# ========== Logging ==========
mkdir -p "$HOME/logs"
LOG_FILE="$HOME/logs/setup-system-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Logging to $LOG_FILE"

echo "========== LHN System (Shared) Setup =========="
echo "Script directory: $SCRIPT_DIR"
date

# ========== Retry Helper ==========
# Usage: retry_cmd <max_attempts> <delay_seconds> <description> command [args...]
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

# ========== Serialise concurrent runs with an flock ==========
# Use a world-writable lock file so any user on the node can take the lock.
( umask 0000 && touch "$LOCKFILE" ) 2>/dev/null || true
chmod 0666 "$LOCKFILE" 2>/dev/null || true

if exec 9>>"$LOCKFILE" 2>/dev/null; then
    if command -v flock >/dev/null 2>&1; then
        echo "Waiting for system-setup lock ($LOCKFILE)..."
        if flock -w 1800 9; then
            echo "Lock acquired."
        else
            echo "Warning: timed out waiting for lock (30 min); proceeding anyway."
        fi
    else
        echo "Warning: 'flock' not available; proceeding without a lock."
    fi
else
    echo "Warning: could not open lock file $LOCKFILE; proceeding without a lock."
fi

# ========== Daily sentinel check (re-checked here, inside the lock) ==========
TODAY="$(date +%F)"
if [[ "${FORCE_SYSTEM_SETUP:-0}" != "1" && -f "$SENTINEL" && "$(cat "$SENTINEL" 2>/dev/null)" == "$TODAY" ]]; then
    echo "System setup already completed today ($TODAY). Nothing to do."
    echo "(Set FORCE_SYSTEM_SETUP=1 to force a full re-run.)"
    exit 0
fi

# ========== Part 1: System Updates ==========
echo ""
echo "========== Part 1: System Updates =========="

# Update package lists and install system dependencies
echo "Updating apt package lists..."
sudo apt-get update

# Consolidated system dependencies for geopandas, plotting, and other R packages.
# build-essential and gfortran compile R packages from source (lobstr, butcher, etc.).
# openssh-client is needed by setup-user.sh for SSH key restoration.
echo "Installing system dependencies..."
retry_cmd 3 30 "apt-get install" \
    sudo apt-get install -y --fix-missing gdal-bin libgdal-dev libgeos-dev libproj-dev libudunits2-dev libfreetype6-dev libpng-dev vim build-essential gfortran openssh-client

# Update pip in base conda
echo "Updating pip in base conda..."
"$OLD_CONDA_PATH/bin/python" -m pip install --upgrade pip

# NOTE: duckdb + plotnine are NOT installed into /opt/conda base here. The
# pyspark-lhn-dev kernel runs from /tmp/lhn_dev-$USER (a clone of base), and
# setup-user.sh installs duckdb (Part 9) and plotnine via requirements.txt
# into that clone directly. Polluting the docker base just costs ~2 min
# during setup and serves no consumer (base isn't registered as a kernel).

# ========== Part 1.5: Install micromamba (fast solver) ==========
#
# /opt/conda ships with conda 4.7.12 — pre-libmamba, classic Python solver.
# That solver explodes on the r_env solve in setup-user.sh Part 5 (40 r-*
# packages, gives 13h+ ETA on r-utf8 conflict resolution).
#
# micromamba is a single ~10 MB static C++ binary that bundles libmamba.
# It solves the same env in seconds and reports unsatisfiable specs
# clearly instead of grinding through hypothetical resolutions.
echo ""
echo "========== Part 1.5: Install micromamba =========="

MICROMAMBA_BIN="/usr/local/bin/micromamba"
if [ -x "$MICROMAMBA_BIN" ]; then
    echo "micromamba already installed at $MICROMAMBA_BIN ($($MICROMAMBA_BIN --version 2>&1 | head -1))"
else
    echo "Installing micromamba (single static binary) → $MICROMAMBA_BIN..."
    # Download to a tarball first (with retry), then extract separately.
    # The old `curl | tar` pipe under `set -eo pipefail` aborted the whole
    # script on any network blip with no retry and no clear error message —
    # the same failure mode we fixed for quarto in Part 2.
    MICROMAMBA_URL="https://micro.mamba.pm/api/micromamba/linux-64/latest"
    MICROMAMBA_TARBALL="/tmp/micromamba-latest.tar.bz2"
    TMP_MM="/tmp/micromamba-install-$$"

    retry_cmd 3 15 "micromamba download" \
        curl -fSL --connect-timeout 30 --max-time 120 -o "$MICROMAMBA_TARBALL" "$MICROMAMBA_URL"

    mkdir -p "$TMP_MM"
    tar -xj -C "$TMP_MM" -f "$MICROMAMBA_TARBALL" bin/micromamba
    sudo mv "$TMP_MM/bin/micromamba" "$MICROMAMBA_BIN"
    sudo chmod +x "$MICROMAMBA_BIN"
    rm -rf "$TMP_MM" "$MICROMAMBA_TARBALL"

    if [ -x "$MICROMAMBA_BIN" ]; then
        echo "Installed: $($MICROMAMBA_BIN --version 2>&1 | head -1)"
    else
        echo "ERROR: micromamba not found at $MICROMAMBA_BIN after install." >&2
        exit 1
    fi
fi

# ========== Part 2: Install Quarto ==========
echo ""
echo "========== Part 2: Install Quarto =========="

# Known-good fallback release, used only when the GitHub API "latest" lookup
# fails (api.github.com rate limits are common from a shared cluster NAT).
# A slightly older quarto beats no quarto for the day.
QUARTO_FALLBACK_TAG="v1.6.43"

if command -v quarto >/dev/null 2>&1 && quarto --version >/dev/null 2>&1; then
    echo "Quarto already installed: $(quarto --version 2>/dev/null) at $(command -v quarto)"
else
    echo "Installing Quarto..."
    # Fetch the latest tag from GitHub API. `|| true` so an API failure
    # (rate limit, network blip) cannot abort the whole setup under set -e;
    # we fall back to the pinned release instead. Previously a rate-limited
    # response here killed setup-system silently, which is one way quarto
    # ended up missing for the day.
    LATEST_TAG=$(curl -fsS https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [[ -z "$LATEST_TAG" ]]; then
        echo "WARNING: could not determine latest Quarto release from the GitHub API."
        echo "         Falling back to pinned release ${QUARTO_FALLBACK_TAG}."
        LATEST_TAG="$QUARTO_FALLBACK_TAG"
    fi
    QUARTO_VERSION=${LATEST_TAG#v} # Remove 'v' prefix if present
    RELEASE_URL="https://github.com/quarto-dev/quarto-cli/releases/download/${LATEST_TAG}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
    QUARTO_TARBALL="/tmp/quarto-${QUARTO_VERSION}.tar.gz"

    # Download to a file first (curl -f + retry), THEN extract. The old
    # `curl | sudo tar` pipe under `set -eo pipefail` aborted the whole
    # setup on any transient failure, with no retry and no clear message.
    retry_cmd 3 15 "quarto download" \
        curl -fSL --connect-timeout 30 --max-time 600 -o "$QUARTO_TARBALL" "$RELEASE_URL"

    sudo mkdir -p "/opt/quarto/${QUARTO_VERSION}"
    echo "Extracting Quarto ${QUARTO_VERSION}..."
    sudo tar -xzf "$QUARTO_TARBALL" -C "/opt/quarto/${QUARTO_VERSION}" --strip-components=1
    rm -f "$QUARTO_TARBALL"
    sudo ln -sf "/opt/quarto/${QUARTO_VERSION}/bin/quarto" "/usr/local/bin/quarto"

    # Verify it actually runs — fail LOUDLY here rather than discovering at
    # render time that quarto never made it onto the node.
    if /usr/local/bin/quarto --version >/dev/null 2>&1; then
        echo "Quarto $(/usr/local/bin/quarto --version 2>/dev/null) installed successfully."
    else
        echo "ERROR: quarto extracted to /opt/quarto/${QUARTO_VERSION} but does not run." >&2
        echo "       Check the download URL and GLIBC compatibility for this release." >&2
        exit 1
    fi
fi

# ========== Part 3: Install Miniconda (shared) ==========
echo ""
echo "========== Part 3: Install Miniconda (shared) =========="

if [ -d "$MINICONDA_PATH" ]; then
    echo "Miniconda already installed at $MINICONDA_PATH. Skipping installation."
else
    echo "Installing Miniconda to $MINICONDA_PATH..."
    # Pin to a Miniconda version compatible with GLIBC 2.27 (Ubuntu 18.04)
    MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py310_23.11.0-2-Linux-x86_64.sh"
    MINICONDA_INSTALLER="/tmp/miniconda.sh"

    # Download with curl, NOT wget. On this Ubuntu 18.04 container wget is built
    # against GnuTLS, which rejects the current Let's Encrypt chain on
    # repo.anaconda.com as "expired" because the container's frozen ca-certificates
    # bundle is stale (and the container is rebuilt daily, so it never updates).
    # curl uses OpenSSL, which validates the same chain fine — confirmed by
    # diagnose-miniconda.sh (curl HEAD -> HTTP 200, wget -> exit 5, 0 bytes).
    # The retry + size check make a failed/truncated download LOUD instead of
    # letting `set -eo pipefail` abort the whole setup silently.
    retry_cmd 3 15 "miniconda download" \
        curl -fSL --connect-timeout 30 --max-time 600 \
        -o "$MINICONDA_INSTALLER" "$MINICONDA_URL"

    INSTALLER_SIZE=$(stat -c '%s' "$MINICONDA_INSTALLER" 2>/dev/null || echo 0)
    if [ "$INSTALLER_SIZE" -lt 50000000 ]; then
        echo "ERROR: Miniconda installer is only ${INSTALLER_SIZE} bytes (expected ~134 MB)." >&2
        echo "       The download from $MINICONDA_URL failed or was truncated." >&2
        echo "       Run ./diagnose-miniconda.sh for a detailed report." >&2
        rm -f "$MINICONDA_INSTALLER"
        exit 1
    fi

    bash "$MINICONDA_INSTALLER" -b -p "$MINICONDA_PATH"
    rm "$MINICONDA_INSTALLER"
fi

# Make the shared Miniconda readable/executable by every user on the node.
# Each user points CONDA_PKGS_DIRS at their own cache (see setup-user.sh), so
# nobody needs write access to this tree after install.
chmod -R a+rX "$MINICONDA_PATH" 2>/dev/null || true
echo "Using Miniconda version compatible with Ubuntu 18.04"

# ========== Mark system setup complete ==========
echo "$TODAY" > "$SENTINEL"
# World-writable so any user on the shared node can refresh it on a later day,
# not just whoever created it first.
chmod 0666 "$SENTINEL" 2>/dev/null || true

echo ""
echo "========== System (Shared) Setup Complete =========="
echo "Sentinel written: $SENTINEL ($TODAY)"
echo ""
echo "Next: each user runs ./setup-user.sh to build their own per-user"
echo "environments (r_env, lhn_prod, lhn_dev) and Jupyter kernels."
echo "Setup completed at: $(date)"
