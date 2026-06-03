#!/bin/bash
# setup-user.sh
#
# Per-user container setup. Safe to run by any user on a shared node — every
# environment, clone and cache path is suffixed with the username, so two
# different users never collide in /tmp even when sharing the same container/node.
#
# This script provisions, for the CURRENT user:
#   1. SSH key restoration (from that user's persistent storage)
#   2. R environment with Python 3.10 and R 4.4.0 (/tmp/r_env-<user>).
#      If another user already built their /tmp/r_env-<other> on this node,
#      it is cloned (fast) instead of solved from scratch. FORCE_R_ENV_SOLVE=1
#      forces a fresh build.
#   3. Two lhn conda environments for side-by-side testing:
#      - lhn_prod: Production monolithic version (v0.1.0)
#      - lhn_dev:  Development refactored version (v0.2.0-dev)
#   4. Jupyter kernels
#
# Shared, machine-wide items (system libraries, Quarto, Miniconda, base-conda
# pip packages) are installed by setup-system.sh. This script runs
# setup-system.sh automatically if the shared setup has not run today.
#
# Prerequisites:
#   - Original Docker conda at /opt/conda with pyspark 2.4.x
#   - SSH keys under ~/work/Users/<username>/.ssh, and that key authorised on
#     GitHub. Part 7 auto-clones lhn and spark_config_mapper into
#     ~/work/Users/<username>/ if they are not already there, so a second user
#     no longer needs to pre-stage those repos by hand — only working SSH.
#
# Usage:
#   chmod +x setup-user.sh
#   ./setup-user.sh
#
# After running, select kernels in JupyterLab:
#   - "PySpark + lhn-prod (v0.1.0)" for production Spark work
#   - "PySpark + lhn-dev (v0.2.0)" for development Spark work
#   - "Python 3.10 (r_env)" for Python ML work
#   - "R 4.4.0 (r_env)" for R analysis

# Note: Not using -u (nounset) because conda activation scripts have unbound variables
set -eo pipefail

# ========== PATH bootstrap (Critical) ==========
#
# In fresh JupyterHub / container terminal sessions, the default $PATH may
# not include /usr/bin (where system tools like ssh, git, sudo from apt
# live) or /opt/conda/bin (the Docker base conda). This can cause
# `command -v ssh` etc. to fail even when the packages are installed on
# the system.
#
# A user who has previously run custom setup or has a long-lived shell
# may already have a more complete PATH. A brand-new terminal session
# often does not.
#
# Make this script self-contained by always normalising PATH to include:
#   - /opt/conda/bin                  (base Docker conda — has git, curl, etc.)
#   - standard Linux system bin dirs  (where apt-installed tools live)
#
# Then source base conda's activation so `conda` + its env-management
# functions are usable. This works whether the user opened a fresh shell
# or had activated a conda env beforehand.
export PATH="/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

if [ -f /opt/conda/etc/profile.d/conda.sh ]; then
    # shellcheck disable=SC1091
    source /opt/conda/etc/profile.d/conda.sh
fi

# ========== Ensure ssh + git are available (no sudo path) ==========
#
# In some container/JupyterHub terminal sessions (fresh shells, certain
# user contexts), ssh and/or git may not be on $PATH even though the
# underlying system packages are installed.
#
# This section provides a fallback: if ssh or git are missing from PATH,
# install them into a small per-user conda tools environment using the
# base conda (which is always available and does not require sudo for
# package installation into that env).
#
# The PATH bootstrap above only helps if the binaries exist somewhere;
# this step ensures they can be made available without relying on
# apt-get (which may or may not be usable depending on the exact
# permissions and whether setup-system.sh has run).
#
# This step is idempotent — once /tmp/setup-tools-<user> exists, subsequent
# runs reuse it (a few seconds vs ~30s for a fresh create).
#
# Note: setup-system.sh itself may perform actions that require sudo
# (apt installs, etc.). If the shared system setup has not completed,
# this script will attempt to invoke it, which may prompt for sudo or
# require a user with appropriate permissions to run setup-system.sh first.

# Pick the user's effective name early so we can suffix per-user paths.
__USER_FOR_TOOLS="${SCD_USER:-${USER:-$(id -un)}}"
SETUP_TOOLS_ENV="/tmp/setup-tools-${__USER_FOR_TOOLS}"

if ! command -v ssh >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo ""
    echo "ssh and/or git not on PATH — installing via conda (no sudo needed)..."

    # Locate a conda binary we can use to bootstrap. Prefer the original
    # Docker conda at /opt/conda; fall back to a previously-installed
    # Miniconda at /tmp/miniconda if available.
    CONDA_BIN=""
    for candidate in /opt/conda/bin/conda /tmp/miniconda/bin/conda; do
        if [ -x "$candidate" ]; then
            CONDA_BIN="$candidate"
            break
        fi
    done

    if [ -z "$CONDA_BIN" ]; then
        echo "FATAL: no conda found at /opt/conda/bin/conda or /tmp/miniconda/bin/conda."
        echo "       The LHN Docker base image should ship with /opt/conda."
        echo "       If you're on a non-standard image, the base conda may be missing."
        exit 1
    fi

    if [ ! -d "$SETUP_TOOLS_ENV" ]; then
        echo "  Creating $SETUP_TOOLS_ENV with openssh + git (~30s)..."
        # --quiet keeps output clean; -c conda-forge for current openssh
        if ! "$CONDA_BIN" create -y --quiet -p "$SETUP_TOOLS_ENV" \
                -c conda-forge openssh git ca-certificates 2>&1 | tail -5; then
            echo "FATAL: conda failed to create $SETUP_TOOLS_ENV."
            echo "       Try: $CONDA_BIN create -y -p $SETUP_TOOLS_ENV -c conda-forge openssh git"
            exit 1
        fi
    else
        echo "  Reusing existing $SETUP_TOOLS_ENV (already has ssh + git)."
    fi

    # Put the tools env's bin FIRST so its ssh + git win over anything else.
    export PATH="$SETUP_TOOLS_ENV/bin:$PATH"

    if ! command -v ssh >/dev/null 2>&1; then
        echo "FATAL: ssh still not on PATH after conda install."
        echo "       Check $SETUP_TOOLS_ENV/bin contents:"
        ls "$SETUP_TOOLS_ENV/bin" 2>/dev/null | head -10 || true
        exit 1
    fi

    echo "  ssh now available: $(command -v ssh)"
    echo "  git now available: $(command -v git)"
    echo ""
fi

# Final sanity check — at this point ssh / git / curl MUST exist.
for tool in ssh git curl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FATAL: '$tool' still not on PATH after bootstrap."
        echo "       PATH=$PATH"
        exit 1
    fi
done

# Configuration
# Using SSH URL (more reliable for git operations). Part 7 clones these into
# the current user's persistent storage if they are not already present, so a
# second user does not have to pre-stage repos by hand — they only need a
# GitHub-authorised SSH key (the same one that let them clone updatebionic).
LHN_REPO_URL="git@github.com:harlananelson/lhn.git"
SPARK_CONFIG_REPO_URL="git@github.com:harlananelson/spark_config_mapper.git"

# Current user — drives every per-user path so two people can run this script
# on the same node without colliding. Override with SCD_USER if ever needed.
CURRENT_USER="${SCD_USER:-${USER:-$(id -un)}}"

# Persistent storage paths (S3 mount - slow but survives container restart)
# Per-user: each user keeps their own clones under ~/work/Users/<username>/
PERSIST_BASE="$HOME/work/Users/$CURRENT_USER"
LHN_PERSIST="$PERSIST_BASE/lhn"
SPARK_CONFIG_PERSIST="$PERSIST_BASE/spark_config_mapper"
OMOP_CONCEPT_PERSIST="$PERSIST_BASE/omop_concept_mapper"

# Temporary paths (fast local disk - wiped on container restart)
# Per-user suffix prevents two users fighting over the same /tmp directories.
LHN_PROD_CLONE="/tmp/lhn_prod_src-$CURRENT_USER"   # Clone for production (v0.1.0-monolithic)

# Conda environment paths (fast local disk, per-user)
PROD_ENV_PATH="/tmp/lhn_prod-$CURRENT_USER"
DEV_ENV_PATH="/tmp/lhn_dev-$CURRENT_USER"
OLD_CONDA_PATH="/opt/conda"

# Shared Miniconda (installed by setup-system.sh) + per-user package cache
MINICONDA_PATH="/tmp/miniconda"
CONDA_PKGS_DIR="/tmp/conda-pkgs-$CURRENT_USER"

# ─── Optional builds ────────────────────────────────────────────────────────
# lhn_prod is the v0.1.0-monolithic environment used by the OLD pipeline.
# Most users only need lhn_dev (v0.2.0) + r_env, so lhn_prod is skipped by
# default. Set BUILD_LHN_PROD=1 to opt back in.
BUILD_LHN_PROD="${BUILD_LHN_PROD:-0}"

# ─── Persistent pip cache ───────────────────────────────────────────────────
# Container restarts wipe /tmp and /home/jovyan/.cache, so every setup-user
# re-run otherwise re-downloads ~500 MB (pyspark 317 MB sdist, pyarrow 38 MB,
# polars 56 MB, numpy + scipy + matplotlib, etc). Point pip's cache at
# persistent storage so those downloads survive. The slow-disk read penalty
# is paid only during install (already slow), not at runtime.
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$PERSIST_BASE/.cache/pip}"
mkdir -p "$PIP_CACHE_DIR" 2>/dev/null || true

# Node-wide system-setup sentinel (written by setup-system.sh).
#
# This node is SHARED: /tmp, /opt and /usr/local are visible to every user,
# so setup-system only needs to run ONCE per node per day (by the first user
# to run it). The sentinel is therefore node-wide, NOT per-user.
#
# Historical note: A previous per-$USER suffix on the sentinel meant that
# a second user on the same node would not see that setup-system had already
# run, causing unnecessary re-execution attempts. This was fixed by making
# the sentinel node-wide (must match the one in setup-system.sh).
SENTINEL="/tmp/.lhn-system-ready"

# Resolve full path to this script (handles both sourced and direct execution)
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$SCRIPT_PATH")"

# Shared system-setup script — run first if it has not run today
SYSTEM_SCRIPT="$SCRIPT_DIR/setup-system.sh"

# ========== Self-Update from GitHub ==========
SELF_UPDATE_REPO="harlananelson/updatebionic"
SELF_UPDATE_BRANCH="main"
SELF_UPDATE_FILE="setup-user.sh"

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

# ========== Auto-fetch sibling scripts (setup-system.sh, requirements*) ==========
#
# If a user bootstrapped via the curl one-liner (downloads only
# setup-user.sh), the sibling files needed for a full setup aren't in
# SCRIPT_DIR. Fetch them on-demand from the same GitHub branch.
#
# Without this, the script exited with
#   ERROR: $SYSTEM_SCRIPT not found and system setup has not run today
# and the user had no clear path forward except cloning the whole repo.
SIBLING_FILES=(
    "setup-system.sh"
    "requirements.txt"
    "requirements-python.txt"
    "requirements-R.txt"
    "environment-ml.yml"
)
for sibling in "${SIBLING_FILES[@]}"; do
    sibling_path="$SCRIPT_DIR/$sibling"
    if [ ! -f "$sibling_path" ]; then
        url="https://raw.githubusercontent.com/${SELF_UPDATE_REPO}/${SELF_UPDATE_BRANCH}/${sibling}"
        echo "Fetching missing sibling file: $sibling..."
        if curl -sfL "$url" > "$sibling_path" 2>/dev/null && [ -s "$sibling_path" ]; then
            echo "  → fetched to $sibling_path"
            [ "$sibling" = "setup-system.sh" ] && chmod +x "$sibling_path"
        else
            rm -f "$sibling_path"  # remove zero-byte / partial download
            echo "  WARNING: could not fetch $sibling from $url"
            echo "           (network blip, or file moved/renamed in repo)"
        fi
    fi
done

echo "========== LHN Per-User Environment Setup =========="
echo "User:             $CURRENT_USER"
echo "Script directory: $SCRIPT_DIR"
date

# ========== Ensure shared system setup has run today ==========
echo ""
echo "========== Ensuring shared system setup =========="
SETUP_TODAY="$(date +%F)"
if [[ -f "$SENTINEL" && "$(cat "$SENTINEL" 2>/dev/null)" == "$SETUP_TODAY" ]]; then
    echo "Shared system setup already completed today ($SETUP_TODAY)."
else
    echo "Shared system setup has not run today."
    if [[ -f "$SYSTEM_SCRIPT" ]]; then
        echo "Running $SYSTEM_SCRIPT (shared items; needs sudo)..."
        if env -u SKIP_SELF_UPDATE bash "$SYSTEM_SCRIPT"; then
            echo "Shared system setup finished."
        else
            echo "ERROR: shared system setup ($SYSTEM_SCRIPT) failed."
            echo "setup-system.sh performs actions that may require sudo (e.g. apt-get)."
            echo "If the current user cannot provide sudo credentials when prompted,"
            echo "ask someone with the necessary permissions on this node to run"
            echo "setup-system.sh first (it is safe and idempotent), then re-run this script."
            exit 1
        fi
    else
        echo "ERROR: $SYSTEM_SCRIPT not found and system setup has not run today."
        echo "Place setup-system.sh (from the updatebionic repo) next to this script"
        echo "and re-run, or run setup-system.sh first (it may require sudo for some steps)."
        exit 1
    fi
fi
if [[ ! -f "$SENTINEL" ]]; then
    echo "ERROR: system sentinel $SENTINEL still missing after setup. Aborting."
    exit 1
fi

# Per-user conda package cache — prevents one user's 'conda clean' from
# wiping packages another user is mid-download of.
echo "Using per-user conda package cache: $CONDA_PKGS_DIR"
mkdir -p "$CONDA_PKGS_DIR"
export CONDA_PKGS_DIRS="$CONDA_PKGS_DIR"

# ========== Retry Helper ==========
# Usage: retry_cmd <max_attempts> <delay_seconds> <description> command [args...]
# Retries a command up to max_attempts times with delay between attempts.
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

# Ensure conda environments registry exists (suppresses "Unable to create environments file" warning)
mkdir -p ~/.conda
touch ~/.conda/environments.txt 2>/dev/null || true

# ========== Part 1: Install SSH and Restore Keys ==========
echo ""
echo "========== Part 1: Install SSH and Restore Keys =========="

# openssh-client is installed by setup-system.sh — just sanity-check it here.
if ! command -v ssh &> /dev/null; then
    echo "Warning: ssh not found — setup-system.sh should have installed it."
fi

# Create ~/.ssh directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Persistent SSH key storage location (per-user)
SSH_PERSIST_DIR="$PERSIST_BASE/.ssh"

# Restore SSH keys from persistent storage if they exist
if [[ -d "$SSH_PERSIST_DIR" ]] && [[ -n "$(ls -A "$SSH_PERSIST_DIR" 2>/dev/null)" ]]; then
    echo "Restoring SSH keys from persistent storage ($SSH_PERSIST_DIR)..."
    cp -n "$SSH_PERSIST_DIR"/* ~/.ssh/ 2>/dev/null || true
    # Set correct permissions on private keys (read/write for owner only)
    chmod 600 ~/.ssh/id_* 2>/dev/null || true
    # Set correct permissions on public keys (readable by others)
    chmod 644 ~/.ssh/*.pub 2>/dev/null || true
    # Restore known_hosts if present
    [[ -f "$SSH_PERSIST_DIR/known_hosts" ]] && cp -n "$SSH_PERSIST_DIR/known_hosts" ~/.ssh/
    echo "SSH keys restored successfully."

    # Start ssh-agent and add key (so passphrase is only entered once)
    echo "Starting ssh-agent..."
    eval "$(ssh-agent -s)"

    # Support non-interactive passphrase entry via SSH_KEY_PASSPHRASE env var
    # This enables automation (e.g., Playwright MCP) without manual input.
    # If SSH_KEY_PASSPHRASE is not set, falls back to interactive prompt.
    if [[ -n "${SSH_KEY_PASSPHRASE:-}" ]]; then
        echo "Adding SSH key to agent (using SSH_KEY_PASSPHRASE)..."
        # Create a temporary askpass script that echoes the passphrase
        ASKPASS_SCRIPT=$(mktemp /tmp/ssh-askpass-XXXXXX)
        cat > "$ASKPASS_SCRIPT" <<ASKEOF
#!/bin/bash
echo "\$SSH_KEY_PASSPHRASE"
ASKEOF
        chmod +x "$ASKPASS_SCRIPT"
        # Use SSH_ASKPASS with DISPLAY unset to force askpass usage
        SSH_ASKPASS="$ASKPASS_SCRIPT" SSH_ASKPASS_REQUIRE=force ssh-add ~/.ssh/id_ed25519 </dev/null
        rm -f "$ASKPASS_SCRIPT"
    else
        echo "Adding SSH key to agent (you'll be prompted for passphrase once)..."
        ssh-add ~/.ssh/id_ed25519
    fi

    # Test GitHub connectivity
    echo "Testing GitHub SSH connectivity..."
    ssh -T git@github.com 2>&1 | head -2 || true
else
    echo "ERROR: No SSH keys found in persistent storage at $SSH_PERSIST_DIR"
    echo ""
    echo "FIRST-TIME SETUP INSTRUCTIONS:"
    echo "1. Generate an SSH key:"
    echo "   ssh-keygen -t ed25519 -C \"your_email@example.com\""
    echo ""
    echo "2. Copy to persistent storage:"
    echo "   mkdir -p $SSH_PERSIST_DIR"
    echo "   cp ~/.ssh/id_ed25519 $SSH_PERSIST_DIR/"
    echo "   cp ~/.ssh/id_ed25519.pub $SSH_PERSIST_DIR/"
    echo ""
    echo "3. Add the public key to GitHub:"
    echo "   cat ~/.ssh/id_ed25519.pub"
    echo "   (Copy output to GitHub.com -> Settings -> SSH keys)"
    echo ""
    echo "4. Re-run this script after setup."
    exit 1
fi

# ========== Part 2: Initialise Miniconda (shared) ==========
echo ""
echo "========== Part 2: Initialise Miniconda (shared) =========="

# System libraries, Quarto, base-conda pip packages and Miniconda itself are
# all installed by setup-system.sh (the shared, run-once-per-boot script).
# This per-user script only consumes them.
if [[ ! -d "$MINICONDA_PATH" ]]; then
    echo "ERROR: shared Miniconda not found at $MINICONDA_PATH."
    echo "setup-system.sh is responsible for installing it. Re-run setup-system.sh."
    exit 1
fi

# Set PATH to include the shared Miniconda
export PATH="$MINICONDA_PATH/bin:$PATH"

# Initialize Conda shell hook for activation in this script
eval "$(conda shell.bash hook)"

# Add channels (writes to the per-user ~/.condarc)
echo "Configuring conda channels..."
conda config --add channels conda-forge
conda config --set channel_priority strict

# Clean only this user's package cache ($CONDA_PKGS_DIRS, set above)
echo "Cleaning per-user conda cache..."
conda clean --all -y

# ========== Part 5: Create R Environment ==========
echo ""
echo "========== Part 5: Create R Environment =========="

R_VERSION="4.4.0"
PYTHON_VERSION="3.10"
R_ENV_PATH="/tmp/r_env-$CURRENT_USER"

if [ -d "$R_ENV_PATH" ]; then
    echo "R environment already exists at $R_ENV_PATH. Removing and recreating..."
    conda env remove -p "$R_ENV_PATH" -y 2>/dev/null || rm -rf "$R_ENV_PATH"
fi

# micromamba is used for the from-scratch solve below and the geospatial
# follow-up further down; define its path once, up front.
MICROMAMBA_BIN="/usr/local/bin/micromamba"
RETRY_COUNT=0
MAX_RETRIES=3

# ── Reuse another user's r_env if one already exists on this shared node ──
# Each user keeps their OWN /tmp/r_env-<user> (isolation — no mid-session
# collisions if someone re-runs setup), but the env content is identical
# across users and building it is expensive (micromamba solve + CRAN/GitHub
# compile). If a sibling /tmp/r_env-<other> is already fully built, clone it:
# a fast local copy that skips the solve AND every package-install step below
# (geospatial, pip, CRAN, GitHub). `conda create --clone` copies the entire
# env prefix, including the install.packages / remotes::install_github
# libraries that live inside it. Set FORCE_R_ENV_SOLVE=1 to force a fresh
# from-scratch build instead.
CLONED_R_ENV=0
if [ -z "${FORCE_R_ENV_SOLVE:-}" ]; then
    for candidate in /tmp/r_env-*; do
        [ "$candidate" = "$R_ENV_PATH" ] && continue
        [ -x "$candidate/bin/R" ] || continue           # complete env only
        [ -d "$candidate/lib/R/library" ] || continue   # R library populated
        echo "Found a sibling R environment at $candidate (built by another user)."
        echo "Cloning it to $R_ENV_PATH — skips the solve + CRAN/GitHub builds..."
        # Use the *shared Miniconda's conda* explicitly for the clone. The sibling
        # r_env was built under /tmp/miniconda; using whatever `conda` is first in
        # PATH here (often the old /opt/conda because of early PATH bootstrap) can
        # produce an env that later `conda activate` (or kernel launch) doesn't
        # fully switch to, leading to python/R resolution picking the wrong (old)
        # interpreters for registration and at runtime in R notebooks.
        MINICONDA_CONDA="/tmp/miniconda/bin/conda"
        if [ -x "$MINICONDA_CONDA" ]; then
            CLONE_CMD=("$MINICONDA_CONDA" "create" "-p" "$R_ENV_PATH" "--clone" "$candidate" "-y")
        else
            CLONE_CMD=(conda create -p "$R_ENV_PATH" --clone "$candidate" "-y")
        fi
        if "${CLONE_CMD[@]}"; then
            CLONED_R_ENV=1
            echo "  ✓ Cloned R environment from $candidate."
        else
            echo "  ⚠  Clone failed — falling back to a full from-scratch solve."
            rm -rf "$R_ENV_PATH"
        fi
        break
    done
fi

if [ "$CLONED_R_ENV" -eq 0 ]; then
    # Read R conda specs from requirements-R.txt (strip comments + blank lines).
    # Combined into the conda create call below so all R packages are solved at
    # env-creation time — a single solve, not "create then add to existing env".
    # The two-step pattern (conda create r-base + conda install r-tidyverse ...)
    # triggers the classic Python solver's conflict-resolution explosion on
    # conda 4.7 (13+ hour ETA on r-utf8). One-shot conda create avoids it.
    REQUIREMENTS_R="$SCRIPT_DIR/requirements-R.txt"
    if [[ -f "$REQUIREMENTS_R" ]]; then
        R_CONDA_SPECS=$(grep -v '^[[:space:]]*#' "$REQUIREMENTS_R" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
        echo "Including $(echo $R_CONDA_SPECS | wc -w) R packages from $REQUIREMENTS_R in env-creation solve."
    else
        echo "Warning: $REQUIREMENTS_R not found. Falling back to a minimal R spec."
        R_CONDA_SPECS="r-tidyverse r-devtools r-irkernel"
    fi

    # Always prefer the shared Miniconda + its micromamba for the r_env solve.
    # This guarantees the resulting env (R 4.x + Python 3.10) is under the
    # *updated* conda, not accidentally created under the old /opt/conda.
    # That isolation is the whole point of the "old conda for spark, new
    # miniconda for R notebooks" design.
    MINICONDA_CONDA="/tmp/miniconda/bin/conda"
    if [ -x "$MICROMAMBA_BIN" ]; then
        SOLVER_DESC="micromamba ($($MICROMAMBA_BIN --version 2>&1 | head -1)) via miniconda"
        SOLVE_CMD=("$MICROMAMBA_BIN" "create" "-y" "-p" "$R_ENV_PATH" "-c" "conda-forge")
    elif [ -x "$MINICONDA_CONDA" ]; then
        SOLVER_DESC="miniconda conda (libmamba if configured)"
        SOLVE_CMD=("$MINICONDA_CONDA" "create" "-y" "-p" "$R_ENV_PATH" "-c" "conda-forge")
    else
        SOLVER_DESC="PATH conda (slow/fallback — miniconda not found)"
        SOLVE_CMD=(conda create -y -p "$R_ENV_PATH" -c conda-forge)
    fi

    echo "Creating R ${R_VERSION} environment with Python ${PYTHON_VERSION} + R packages (single-shot solve)..."
    echo "Solver: $SOLVER_DESC"
    until [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]
    do
        # Note: -c conda-forge applies to ALL specs on this command line, including
        # the R-package set. r-rcpptoml is pinned here because the old code added
        # it in a separate `conda install` step (a second solve) for reticulate.
        "${SOLVE_CMD[@]}" \
            python=${PYTHON_VERSION} r-base=${R_VERSION} cmake r-rcpptoml \
            $R_CONDA_SPECS && break
        RETRY_COUNT=$((RETRY_COUNT+1))
        echo "Environment creation failed. Retrying... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
        sleep 5
    done
fi
if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
    echo "ERROR: Conda environment creation failed after $MAX_RETRIES attempts."
    echo "Continuing with lhn setup (R environment will not be available)..."
else
    # Activate R environment for package installation.
    # Force the *miniconda* (the one that owns the r_env we just built/cloned)
    # rather than whatever `conda` the early PATH bootstrap left first in $PATH.
    # This is required for `python` and `R` lookups during registration (and for
    # the kernel to behave correctly at runtime) to resolve inside the modern
    # r_env rather than the old Docker /opt/conda.
    if [ -f /tmp/miniconda/etc/profile.d/conda.sh ]; then
        # shellcheck disable=SC1091
        source /tmp/miniconda/etc/profile.d/conda.sh
    fi
    export PATH="/tmp/miniconda/bin:$PATH"
    conda activate "$R_ENV_PATH" || echo "WARNING: conda activate $R_ENV_PATH returned non-zero (proceeding with explicit paths for registration)"

    # Configure environment variables
    export R_INCLUDE_DIR="$R_ENV_PATH/lib/R/include"
    export R_LIB_PATH="$R_ENV_PATH/lib/R/library"
    export PKG_CONFIG_PATH="$R_ENV_PATH/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

    # Configure .Rprofile
    echo "Configuring .Rprofile..."
    cat > "$HOME/.Rprofile" <<EOF
if (.libPaths()[1] != "$R_ENV_PATH/lib/R/library") {
  .libPaths(c("$R_ENV_PATH/lib/R/library", .libPaths()))
}
EOF

    # The expensive package-install steps below (geospatial conda solve,
    # CRAN compile, GitHub compile) are skipped when the env was cloned from
    # a sibling user — the clone already carries those libraries. The per-user
    # Jupyter kernel registrations further down run either way, since kernels
    # live in $HOME and are not part of the cloned env prefix.
    if [ "$CLONED_R_ENV" -eq 0 ]; then
        # ─── Geospatial R packages (separate, non-fatal solve) ────────────────
        # r-sf and r-units pull libgdal-core / libxml2 versions that conflict
        # with r-base=4.4.0 in the main env-creation solve (commented out in
        # requirements-R.txt). Try them in a smaller follow-up solve here —
        # the smaller spec set is much more likely to resolve. If it still
        # fails, log a warning and continue: usmap/usmapdata GitHub installs
        # may fail, but everything non-geospatial works.
        echo ""
        echo "Attempting separate geospatial R packages solve (r-sf, r-units)..."
        if [ -x "$MICROMAMBA_BIN" ]; then
            GEO_INSTALL=("$MICROMAMBA_BIN" "install" "-y" "-p" "$R_ENV_PATH" "-c" "conda-forge")
        else
            GEO_INSTALL=(conda install -y -p "$R_ENV_PATH" -c conda-forge)
        fi
        if "${GEO_INSTALL[@]}" r-sf r-units; then
            echo "  ✓ Geospatial R packages installed."
        else
            echo ""
            echo "  ⚠  WARNING: r-sf / r-units install failed — conda-forge libgdal stack"
            echo "             may be temporarily incompatible with r-base=4.4.0."
            echo "             Consequences: GitHub usmap and usmapdata installs may"
            echo "             also fail. Everything else (tidyverse, tidymodels,"
            echo "             targets, survival, etc.) is unaffected."
        fi

        # Install Python packages for R environment
        echo "Installing Python packages for R environment..."
        REQUIREMENTS_PYTHON="$SCRIPT_DIR/requirements-python.txt"
        if [[ -f "$REQUIREMENTS_PYTHON" ]]; then
            python -m pip install -r "$REQUIREMENTS_PYTHON"
        else
            echo "Warning: $REQUIREMENTS_PYTHON not found. Installing critical packages..."
            python -m pip install numpy pandas scikit-learn matplotlib seaborn plotnine
        fi

        # nbformat + nbconvert are already in requirements-python.txt — no
        # second pip install needed. (Old script ran a redundant pass that
        # printed ~30 lines of "Requirement already satisfied".)

        # Install txtarchive from persistent storage
        TXTARCHIVE_PERSIST="$PERSIST_BASE/txtarchive"
        if [[ -d "$TXTARCHIVE_PERSIST" ]]; then
            echo "Installing txtarchive from $TXTARCHIVE_PERSIST..."
            python -m pip install "$TXTARCHIVE_PERSIST"
        else
            echo "Warning: txtarchive not found at $TXTARCHIVE_PERSIST (skipping)"
        fi

        # R packages from requirements-R.txt + r-rcpptoml were already installed
        # in the single-shot `conda create` above. No second conda-install pass
        # needed — which is the whole point of the single-shot solve.

        # Install R packages via CRAN
        echo "Installing R packages via CRAN..."
        R_PACKAGES_CRAN=("ggsurvfit" "themis" "estimability" "mvtnorm" "numDeriv" "emmeans" "Delta" "vip" "IRkernel" "reticulate" "visNetwork" "config" "sparklyr" "table1" "tableone" "equatiomatic" "svglite" "survRM2" "lobstr" "butcher" "probably" "shades" "ggfittext" "gggenes" "kernelshap" "shapviz" "ggdag" "msm" "flexsurv" "mstate" "JMbayes2" "fdapace" "nlme" "TrialEmulation" "randomForestSRC" "timeROC" "data.tree" "DiagrammeR" "cmprsk" "doParallel" "mets" "plotrix" "Publish" "glmnet" "riskRegression" "timereg" "pec" "parameters" "skimr" "smd")
        R_CRAN_PACKAGES_QUOTED=$(printf "'%s'," "${R_PACKAGES_CRAN[@]}")
        R_CRAN_PACKAGES_QUOTED=${R_CRAN_PACKAGES_QUOTED%,}
        R -e ".libPaths(c('$R_LIB_PATH', .libPaths())); pkgs <- c(${R_CRAN_PACKAGES_QUOTED}); missing_pkgs <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]; if (length(missing_pkgs) > 0) { install.packages(missing_pkgs, lib='$R_LIB_PATH', repos='https://cloud.r-project.org') }"

        # Install GitHub-only R packages
        echo "Installing R packages from GitHub..."
        R -e "if (!requireNamespace('treeshap', quietly=TRUE)) remotes::install_github('ModelOriented/treeshap', lib='$R_LIB_PATH')"
        R -e "if (!requireNamespace('usmapdata', quietly=TRUE)) remotes::install_github('pdil/usmapdata', lib='$R_LIB_PATH', dependencies=TRUE)"
        R -e "if (!requireNamespace('usmap', quietly=TRUE)) remotes::install_github('pdil/usmap', lib='$R_LIB_PATH', dependencies=TRUE)"
    else
        echo "Cloned env already contains geospatial + Python + CRAN + GitHub packages; skipping rebuilds."
    fi

    # Register Python kernel for R environment (per-user; Jupyter kernels live
    # in $HOME, not inside the env, so this runs whether the env was solved or
    # cloned).
    # Use *full paths* to the r_env interpreters. This is more reliable than
    # relying on `conda activate` having mutated PATH in this script context
    # (multiple condas in PATH, old vs miniconda, clone vs solve, JupyterHub
    # kernel launch env, etc.). Full paths ensure the kernel.json records the
    # correct modern Python 3.10 + R from the miniconda-based r_env, not the
    # old /opt/conda or system ones.
    R_ENV_PYTHON="$R_ENV_PATH/bin/python"
    R_ENV_R="$R_ENV_PATH/bin/R"

    echo "Registering Python 3.10 kernel (using $R_ENV_PYTHON)..."
    "$R_ENV_PYTHON" -m pip install ipykernel
    "$R_ENV_PYTHON" -m ipykernel install --user --name "python310_renv" --display-name "Python 3.10 (r_env)"

    # Register R kernel (per-user). Use full path so the spec is independent of
    # current PATH when the kernel is later launched by JupyterHub.
    echo "Registering R kernel (using $R_ENV_R)..."
    ACTUAL_R_VER=$("$R_ENV_R" --version 2>/dev/null | head -1 | sed 's/R version \([^ ]*\).*/\1/')
    [ -z "$ACTUAL_R_VER" ] && ACTUAL_R_VER="${R_VERSION}"
    "$R_ENV_R" -e "IRkernel::installspec(name = 'r_env', displayname = 'R ${ACTUAL_R_VER} (r_env)')"

    # Ensure reticulate (if installed) will find the Python sibling in this same env
    # when R notebooks run (common need for plotnine etc from R, or general py interop).
    # Patch the just-registered kernel.json to set RETICULATE_PYTHON and a good PATH.
    R_KERNEL_DIR="$HOME/.local/share/jupyter/kernels/r_env"
    if [ -f "$R_KERNEL_DIR/kernel.json" ]; then
        python -c '
import json, os, sys
kpath = os.path.expanduser(sys.argv[1])
r_env = sys.argv[2]
try:
    with open(kpath) as f: k = json.load(f)
except Exception as e:
    print("  (could not read kernel.json for patch:", e, ")")
    sys.exit(0)
k.setdefault("env", {})
k["env"]["RETICULATE_PYTHON"] = r_env + "/bin/python"
# Deliberately do NOT set PATH here. IRkernel writes no PATH, so setting it to
# "<r_env>/bin" would make Jupyter launch the R kernel with ONLY that directory
# on PATH (the kernel.json env replaces the inherited PATH), hiding system tools
# the kernel shells out to (pandoc for knitr, git, gcc, etc.). RETICULATE_PYTHON
# alone is sufficient to point reticulate at the modern Python 3.10 sibling.
with open(kpath, "w") as f: json.dump(k, f, indent=2)
print("  Patched r_env kernel.json with RETICULATE_PYTHON (reticulate -> modern Python 3.10 sibling).")
' "$R_KERNEL_DIR" "$R_ENV_PATH" || true
    fi

    conda deactivate
    echo "R environment setup complete."
fi

# ========== Part 6: Verify Prerequisites for lhn ==========
echo ""
echo "========== Part 6: Verify Prerequisites for lhn =========="

# Check that old conda exists
if [[ ! -d "$OLD_CONDA_PATH" ]]; then
    echo "ERROR: Old conda not found at $OLD_CONDA_PATH"
    echo "This script requires the original Docker conda environment with pyspark."
    exit 1
fi

# Initialize old conda for this shell
echo "Initializing old conda from $OLD_CONDA_PATH..."
# Workaround: Set HOST if not defined (old conda activation scripts expect it)
export HOST="${HOST:-$(hostname)}"
source "$OLD_CONDA_PATH/etc/profile.d/conda.sh"

# Verify pyspark is available in the Docker base environment.
#
# Activate the Docker conda by its PREFIX ($OLD_CONDA_PATH), NOT the bare name
# `base`. By this point we have installed and `conda shell.bash hook`-
# initialised the shared Miniconda (/tmp/miniconda, Python 3.10), so `base`
# resolves to MINICONDA's base, not the Docker /opt/conda base where
# pyspark 2.4.4 lives. pyspark 2.4.4 only imports under Python 3.7: under 3.8+
# its bundled cloudpickle dies with "TypeError: 'bytes' object cannot be
# interpreted as an integer" (types.CodeType gained posonlyargcount in 3.8).
# Activating the prefix names exactly which conda we mean; the interpreter is
# also pinned to that prefix so the check can never silently use Miniconda 3.10.
echo "Verifying pyspark in base environment (old conda for Spark/PySpark compatibility)..."
# The container provides pyspark 2.4.4 via /usr/local/spark for the "old" base.
# Direct `import pyspark` from the /opt/conda python can hit the well-known
# cloudpickle TypeError ('bytes' object...) because the pyspark tree on disk
# was built against py<3.8. The lhn "PySpark + ..." kernels work around this
# by setting PYTHONPATH / launch args appropriately. Treat the known error as
# non-fatal so we can still finish the per-user r_env (for R notebooks) and
# lhn clones.
conda activate "$OLD_CONDA_PATH" 2>/dev/null || true
PY_CHECK="$OLD_CONDA_PATH/bin/python"
if ! $PY_CHECK -c '
import sys
print("  base python:", sys.version.split()[0], sys.executable)
try:
    import pyspark
    print("  pyspark import OK:", pyspark.__version__)
except Exception as e:
    msg = str(e)
    if "bytes" in msg or "cloudpickle" in msg.lower() or "CodeType" in msg:
        print("  (known pyspark 2.4.4 + py>=3.8 cloudpickle incompatibility — expected)")
        print("   lhn PySpark kernels use container launch config to make it work.")
    else:
        print("  pyspark import error (non-cloudpickle):", msg)
        raise
' ; then
    echo "WARNING: pyspark verification had issues, but continuing (R env + lhn setup may still succeed)."
    echo "         The old /opt/conda is kept for Spark compatibility as designed."
fi
conda deactivate 2>/dev/null || true

echo "Prerequisites verified (or tolerated for known old-pyspark case)."

# ========== Part 7: Verify/Update Source Repositories ==========
echo ""
echo "========== Part 7: Verify/Update Source Repositories =========="

# --- Production: Clone lhn to /tmp with v0.1.0-monolithic branch ---
# Skipped when BUILD_LHN_PROD=0 (default) — Part 8 won't consume it.
if [[ "$BUILD_LHN_PROD" == "1" ]]; then
    echo ""
    echo "--- Setting up PRODUCTION source (v0.1.0-monolithic) ---"
    if [[ -d "$LHN_PROD_CLONE" ]]; then
        echo "Removing existing production clone at $LHN_PROD_CLONE..."
        rm -rf "$LHN_PROD_CLONE"
    fi

    echo "Cloning lhn repository for production to /tmp (fast)..."
    git clone "$LHN_REPO_URL" "$LHN_PROD_CLONE"
    git config --global --add safe.directory "$LHN_PROD_CLONE" 2>/dev/null || true
    cd "$LHN_PROD_CLONE"
    git fetch --all --tags
    git checkout v0.1.0-monolithic
    echo "Production clone checked out to v0.1.0-monolithic"
    echo "Available tags:"
    git tag -l
else
    echo ""
    echo "--- Skipping PRODUCTION source clone (BUILD_LHN_PROD=$BUILD_LHN_PROD) ---"
fi

# --- Development: Use existing persistent directories ---
echo ""
echo "--- Verifying DEVELOPMENT sources (persistent storage) ---"

# Verify lhn exists and is on main branch
if [[ -d "$LHN_PERSIST" ]]; then
    echo "Found lhn at $LHN_PERSIST"
    git config --global --add safe.directory "$LHN_PERSIST" 2>/dev/null || true
    cd "$LHN_PERSIST"
    git fetch --all --tags
    # Use older git-compatible command (--show-current requires git 2.22+)
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
        echo "WARNING: lhn is on branch '$CURRENT_BRANCH', switching to 'main'..."
        git checkout main
    fi
    git pull origin main
    echo "lhn updated to latest main branch"
else
    echo "lhn not found at $LHN_PERSIST — cloning it (per-user persistent storage)..."
    mkdir -p "$PERSIST_BASE"
    if git clone "$LHN_REPO_URL" "$LHN_PERSIST"; then
        git config --global --add safe.directory "$LHN_PERSIST" 2>/dev/null || true
        cd "$LHN_PERSIST"
        git checkout main 2>/dev/null || true
        echo "Cloned lhn to $LHN_PERSIST (main branch)."
    else
        echo "ERROR: failed to clone lhn from $LHN_REPO_URL into $LHN_PERSIST."
        echo ""
        echo "This usually means the current user's SSH key lacks GitHub access."
        echo "Verify with:  ssh -T git@github.com   (should greet the user's GitHub account)"
        echo "Then re-run this script, or pre-clone manually:"
        echo "  git clone $LHN_REPO_URL $LHN_PERSIST"
        exit 1
    fi
fi

# Verify spark_config_mapper exists
if [[ -d "$SPARK_CONFIG_PERSIST" ]]; then
    echo "Found spark_config_mapper at $SPARK_CONFIG_PERSIST"
    git config --global --add safe.directory "$SPARK_CONFIG_PERSIST" 2>/dev/null || true
    cd "$SPARK_CONFIG_PERSIST"
    git pull origin main 2>/dev/null || echo "  (pull skipped or failed)"
else
    echo "spark_config_mapper not found at $SPARK_CONFIG_PERSIST — cloning it..."
    mkdir -p "$PERSIST_BASE"
    if git clone "$SPARK_CONFIG_REPO_URL" "$SPARK_CONFIG_PERSIST"; then
        git config --global --add safe.directory "$SPARK_CONFIG_PERSIST" 2>/dev/null || true
        echo "Cloned spark_config_mapper to $SPARK_CONFIG_PERSIST."
    else
        echo "ERROR: failed to clone spark_config_mapper from $SPARK_CONFIG_REPO_URL."
        echo "Check the current user's GitHub SSH access (ssh -T git@github.com), then re-run."
        exit 1
    fi
fi

# Verify omop_concept_mapper exists
if [[ -d "$OMOP_CONCEPT_PERSIST" ]]; then
    echo "Found omop_concept_mapper at $OMOP_CONCEPT_PERSIST"
    git config --global --add safe.directory "$OMOP_CONCEPT_PERSIST" 2>/dev/null || true
    cd "$OMOP_CONCEPT_PERSIST"
    git pull origin main 2>/dev/null || echo "  (pull skipped or failed)"
else
    echo "WARNING: omop_concept_mapper not found at $OMOP_CONCEPT_PERSIST"
    echo "Will skip installation (may not be required)"
fi

echo ""
echo "Source repositories ready."

# ========== Part 8: Create Production Environment (v0.1.0) ==========
echo ""
echo "========== Part 8: Create Production Environment (lhn_prod) =========="

# lhn_prod (v0.1.0-monolithic) is only used by the OLD pipeline's
# `pyspark-lhn-prod` kernel. Most users only need lhn_dev + r_env, so this
# whole section is skipped by default. Set BUILD_LHN_PROD=1 to opt back in.
if [[ "$BUILD_LHN_PROD" != "1" ]]; then
    echo "Skipping lhn_prod build (BUILD_LHN_PROD=$BUILD_LHN_PROD)."
    echo "  → Set BUILD_LHN_PROD=1 to enable. This saves ~5 min and ~1 GB."
    echo "  → If you need the pyspark-lhn-prod kernel, re-run with:"
    echo "      BUILD_LHN_PROD=1 bash $0"
else

# Remove existing environment if present
if [[ -d "$PROD_ENV_PATH" ]]; then
    echo "Removing existing production environment..."
    conda env remove -p "$PROD_ENV_PATH" -y 2>/dev/null || rm -rf "$PROD_ENV_PATH"
fi

# Clone the Docker base environment (Python 3.7 + pyspark 2.4.4).
# Clone by PREFIX ($OLD_CONDA_PATH), not the bare name `base`: with Miniconda
# active, `--clone base` would clone Miniconda 3.10 instead of the Docker base,
# producing an lhn env that can't import pyspark 2.4.4.
echo "Cloning Docker base environment ($OLD_CONDA_PATH) to $PROD_ENV_PATH..."
echo "This may take a few minutes..."
"$OLD_CONDA_PATH/bin/conda" create -p "$PROD_ENV_PATH" --clone "$OLD_CONDA_PATH" -y

# Activate and install lhn v0.1.0
echo "Activating production environment..."
conda activate "$PROD_ENV_PATH"

# Fix corrupted pip in cloned environment before upgrading
# Cloning conda environments can leave pip in a broken state with mixed version files
echo "Removing corrupted pip installation from cloned environment..."
find "$PROD_ENV_PATH/lib/python3.7/site-packages" -maxdepth 1 -name "pip*" -exec rm -rf {} + 2>/dev/null || true
echo "Installing fresh pip via get-pip.py..."
curl -sS https://bootstrap.pypa.io/pip/3.7/get-pip.py | python

# Upgrade pip to latest version compatible with Python 3.7
echo "Upgrading pip..."
python -m pip install --upgrade pip

# Install lhn with --no-build-isolation to prevent pandas corruption
# The build isolation feature can install newer setuptools that conflict with pandas 0.25.3
echo "Installing lhn v0.1.0 (monolithic) in editable mode..."
pip install --no-build-isolation -e "$LHN_PROD_CLONE"

# Fix corrupted pandas installation from conda clone
# The cloned environment has mixed pandas files from different versions
# We need to completely remove and reinstall pandas cleanly
echo "Fixing corrupted pandas installation..."
pip uninstall pandas -y 2>/dev/null || true
# Remove any leftover pandas files that pip uninstall might miss
rm -rf "$PROD_ENV_PATH/lib/python3.7/site-packages/pandas"
rm -rf "$PROD_ENV_PATH/lib/python3.7/site-packages/pandas-*.dist-info"
# Clear pip cache and install fresh
pip cache purge 2>/dev/null || true
echo "Installing pandas 0.25.3 fresh (for pyspark 2.4.4 compatibility)..."
pip install --no-cache-dir pandas==0.25.3

# Install additional packages from requirements.txt (same as updatebionic-ml.sh)
# These packages are needed by lhn for plotting and data analysis
echo "Installing additional Python packages (plotnine, lifelines, etc.)..."
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"
if [[ -f "$REQUIREMENTS_FILE" ]]; then
    pip install -r "$REQUIREMENTS_FILE"
else
    echo "Warning: $REQUIREMENTS_FILE not found, installing critical packages individually..."
    pip install plotnine lifelines
fi

# Restore pandas 0.25.3 after requirements.txt (transitive deps may have upgraded it)
# pyspark 2.4.4 requires pandas 0.25.x
echo "Restoring pandas 0.25.3 (required for pyspark 2.4.4 compatibility)..."
pip install --no-cache-dir pandas==0.25.3 --force-reinstall

# Install ipykernel and register
echo "Installing ipykernel..."
pip install ipykernel

echo "Registering Jupyter kernel for production environment..."
python -m ipykernel install --user --name "lhn_prod" --display-name "Python (lhn-prod v0.1.0)"

# Verify installation
echo "Verifying lhn installation..."
python -c "import lhn; print(f'lhn imported successfully')" || echo "WARNING: lhn import failed"

conda deactivate

fi   # end BUILD_LHN_PROD guard (Part 8)

# ========== Part 9: Create Development Environment (v0.2.0-dev) ==========
echo ""
echo "========== Part 9: Create Development Environment (lhn_dev) =========="

# Remove existing environment if present
if [[ -d "$DEV_ENV_PATH" ]]; then
    echo "Removing existing development environment..."
    conda env remove -p "$DEV_ENV_PATH" -y 2>/dev/null || rm -rf "$DEV_ENV_PATH"
fi

# Clone the Docker base environment (Python 3.7 + pyspark 2.4.4).
# Clone by PREFIX ($OLD_CONDA_PATH), not the bare name `base`: with Miniconda
# active, `--clone base` would clone Miniconda 3.10 instead of the Docker base,
# producing an lhn_dev env that can't import pyspark 2.4.4.
echo "Cloning Docker base environment ($OLD_CONDA_PATH) to $DEV_ENV_PATH..."
echo "This may take a few minutes..."
"$OLD_CONDA_PATH/bin/conda" create -p "$DEV_ENV_PATH" --clone "$OLD_CONDA_PATH" -y

# Activate and install lhn v0.2.0-dev
echo "Activating development environment..."
conda activate "$DEV_ENV_PATH"

# Fix corrupted pip in cloned environment before upgrading
# Cloning conda environments can leave pip in a broken state with mixed version files
echo "Removing corrupted pip installation from cloned environment..."
find "$DEV_ENV_PATH/lib/python3.7/site-packages" -maxdepth 1 -name "pip*" -exec rm -rf {} + 2>/dev/null || true
echo "Installing fresh pip via get-pip.py..."
curl -sS https://bootstrap.pypa.io/pip/3.7/get-pip.py | python

# Upgrade pip to support pyproject.toml-only editable installs (requires pip >= 21.3)
# Old pip (20.0.2) requires setup.py for editable installs
echo "Upgrading pip to support modern package formats..."
python -m pip install --upgrade pip

# Fix corrupted pandas installation from conda clone
# The cloned environment has mixed pandas files from different versions
echo "Fixing corrupted pandas installation..."
pip uninstall pandas -y 2>/dev/null || true
rm -rf "$DEV_ENV_PATH/lib/python3.7/site-packages/pandas"
rm -rf "$DEV_ENV_PATH/lib/python3.7/site-packages/pandas-*.dist-info"
pip cache purge 2>/dev/null || true
echo "Installing pandas 0.25.3 fresh (for pyspark 2.4.4 compatibility)..."
pip install --no-cache-dir pandas==0.25.3

echo "Installing dependencies for refactored lhn from persistent storage..."

# Install spark_config_mapper first (required dependency)
# Note: Using --no-deps because spark_config_mapper requires pandas>=1.0.0,
# but we need pandas 0.25.3 for pyspark 2.4.4 compatibility.
echo "Installing spark_config_mapper from $SPARK_CONFIG_PERSIST..."
echo "  (Using --no-deps to avoid pandas version conflict with pyspark 2.4.4)"
pip install --no-deps -e "$SPARK_CONFIG_PERSIST"

# Install omop_concept_mapper (may be required)
if [[ -d "$OMOP_CONCEPT_PERSIST" ]]; then
    echo "Installing omop_concept_mapper from $OMOP_CONCEPT_PERSIST..."
    echo "  (Using --no-deps to avoid pandas version conflict)"
    pip install --no-deps -e "$OMOP_CONCEPT_PERSIST" || echo "Note: omop_concept_mapper install failed (may not be needed)"
else
    echo "Skipping omop_concept_mapper (not found)"
fi

# Now install lhn v0.2.0-dev from persistent storage
# Note: Using --no-deps because lhn's pyproject.toml requires pandas>=1.0.0,
# but we need pandas 0.25.3 for pyspark 2.4.4 compatibility.
# The code should still work with pandas 0.25.3.
echo "Installing lhn v0.2.0-dev (refactored) from $LHN_PERSIST..."
echo "  (Using --no-deps to avoid pandas version conflict with pyspark 2.4.4)"
pip install --no-deps -e "$LHN_PERSIST"

# Install additional packages from requirements.txt (same as updatebionic-ml.sh)
# These packages are needed by lhn for plotting and data analysis
echo "Installing additional Python packages (plotnine, lifelines, etc.)..."
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"
if [[ -f "$REQUIREMENTS_FILE" ]]; then
    pip install -r "$REQUIREMENTS_FILE"
else
    echo "Warning: $REQUIREMENTS_FILE not found, installing critical packages individually..."
    pip install plotnine lifelines
fi

# Install duckdb for scd_phenotyping (ICD phenotype classification)
echo "Installing duckdb..."
pip install duckdb

# Restore pandas 0.25.3 after requirements.txt (transitive deps may have upgraded it)
# pyspark 2.4.4 requires pandas 0.25.x
echo "Restoring pandas 0.25.3 (required for pyspark 2.4.4 compatibility)..."
pip install --no-cache-dir pandas==0.25.3 --force-reinstall

# Install ipykernel and register
echo "Installing ipykernel..."
pip install ipykernel

echo "Registering Jupyter kernel for development environment..."
python -m ipykernel install --user --name "lhn_dev" --display-name "Python (lhn-dev v0.2.0)"

# Verify installation
echo "Verifying lhn installation..."
python -c "import lhn; print(f'lhn imported successfully')" || echo "WARNING: lhn import failed"
python -c "import duckdb; print(f'duckdb {duckdb.__version__} installed')" || echo "WARNING: duckdb import failed"

conda deactivate

# ========== Part 10: Summary and Instructions ==========
echo ""
echo "========== Setup Complete! =========="
echo ""
echo "Created two conda environments with lhn:"
echo ""
echo "  PRODUCTION (monolithic v0.1.0):"
echo "    Environment: $PROD_ENV_PATH"
echo "    Source code: $LHN_PROD_CLONE"
echo "    Kernel: Python (lhn-prod v0.1.0)"
echo "    Activate: conda activate $PROD_ENV_PATH"
echo ""
echo "  DEVELOPMENT (refactored v0.2.0-dev):"
echo "    Environment: $DEV_ENV_PATH"
echo "    Source code: $LHN_PERSIST (persistent)"
echo "    Dependencies: $SPARK_CONFIG_PERSIST"
echo "                  $OMOP_CONCEPT_PERSIST"
echo "    Kernel: Python (lhn-dev v0.2.0)"
echo "    Activate: conda activate $DEV_ENV_PATH"
echo ""
echo "========== Jupyter Kernel Usage =========="
echo ""
echo "RECOMMENDED (with Hive metastore access):"
echo "  - PySpark + lhn-prod (v0.1.0)  <- Use this for production testing"
echo "  - PySpark + lhn-dev (v0.2.0)   <- Use this for development testing"
echo ""
echo "These hybrid kernels have full database access and lhn pre-loaded."
echo "No sys.path modification needed!"
echo ""
echo "ALTERNATIVE (no metastore, for non-Spark testing only):"
echo "  - Python (lhn-prod v0.1.0)"
echo "  - Python (lhn-dev v0.2.0)"
echo ""
echo "========== Editable Installs =========="
echo ""
echo "Both environments use editable installs (-e), so:"
echo "  - Changes to $LHN_PROD_CLONE affect the production env (temp, lost on restart)"
echo "  - Changes to $LHN_PERSIST affect the development env (persistent)"
echo ""
echo "Production source is in /tmp (fast but ephemeral)."
echo "Development source is in ~/work (persistent S3 mount)."
echo ""
echo "========== Pandas Version Note =========="
echo ""
echo "IMPORTANT: Both environments use pandas 0.25.3 (from base conda)"
echo "for compatibility with pyspark 2.4.4."
echo ""
echo "The pyproject.toml files in spark_config_mapper and lhn v0.2.0"
echo "require pandas>=1.0.0, but this was bypassed using --no-deps."
echo ""
echo "If you encounter pandas-related import errors, the code may need"
echo "to be updated to support pandas 0.25.x API."
echo ""
echo "========== Hive Metastore Note =========="
echo ""
echo "IMPORTANT: The lhn_prod and lhn_dev kernels may NOT have access to"
echo "the Hive metastore (you'll only see 'default' database)."
echo ""
echo "The base pyspark kernel has the metastore configuration."
echo ""
echo "RECOMMENDED: Use the 'pyspark' kernel with sys.path modification:"
echo ""
echo "  # For PRODUCTION testing (add to top of notebook):"
echo "  import sys"
echo "  sys.path.insert(0, '$LHN_PROD_CLONE')"
echo "  import lhn"
echo ""
echo "  # For DEVELOPMENT testing (add to top of notebook):"
echo "  import sys"
echo "  sys.path.insert(0, '$SPARK_CONFIG_PERSIST')"
echo "  sys.path.insert(0, '$LHN_PERSIST')"
echo "  import lhn"
echo ""
echo "========== Creating Hybrid Kernels (pyspark + lhn) =========="
echo ""
echo "Creating kernels that use base pyspark (with metastore) + lhn paths..."

# Find the py4j zip file for PYTHONPATH
PY4J_ZIP=$(ls /usr/local/spark/python/lib/py4j-*-src.zip 2>/dev/null | head -1)
if [ -z "$PY4J_ZIP" ]; then
  PY4J_ZIP="/usr/local/spark/python/lib/py4j-0.10.7-src.zip"
fi

# Kernel env notes (match the cluster-shipped /usr/local/share/jupyter/
# kernels/pyspark kernel, which is known to work on HDL worker nodes):
#
#   PYSPARK_DRIVER_PYTHON = /opt/conda/bin/python
#     The driver runs on the Jupyter kernel-launch node where
#     /opt/conda/bin/python exists; this matches the ipykernel launcher.
#
#   PYSPARK_PYTHON = python3
#     Executors run on Spark worker nodes which do NOT have /opt/conda/.
#     They have `python3` on PATH (compatible with pyspark 2.4). Setting
#     PYSPARK_PYTHON to an absolute driver-only path causes tasks to fail
#     at worker spawn with "Cannot run program /opt/conda/bin/python:
#     No such file or directory".
#
#   PYSPARK_SUBMIT_ARGS = "--master yarn --deploy-mode client pyspark-shell"
#     Matches the system pyspark kernel. Forces yarn-client mode at
#     Spark init so the SparkContext is built with the right executor
#     env from the start (rather than inheriting whatever the bare
#     kernel launch had).

# Create kernel directory for pyspark-lhn-prod
KERNEL_DIR_PROD="$HOME/.local/share/jupyter/kernels/pyspark-lhn-prod"
mkdir -p "$KERNEL_DIR_PROD"
cat > "$KERNEL_DIR_PROD/kernel.json" << EOF
{
  "argv": ["/opt/conda/bin/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "PySpark + lhn-prod (v0.1.0)",
  "language": "python",
  "env": {
    "SPARK_HOME": "/usr/local/spark",
    "HADOOP_CONF_DIR": "/etc/jupyter/configs",
    "PYTHONPATH": "$LHN_PROD_CLONE:/usr/local/spark/python:$PY4J_ZIP:\${PYTHONPATH}",
    "PYSPARK_PYTHON": "python3",
    "PYSPARK_DRIVER_PYTHON": "/opt/conda/bin/python",
    "PYSPARK_SUBMIT_ARGS": "--master yarn --deploy-mode client pyspark-shell"
  }
}
EOF
echo "Created: PySpark + lhn-prod (v0.1.0)"

# Create kernel directory for pyspark-lhn-dev
KERNEL_DIR_DEV="$HOME/.local/share/jupyter/kernels/pyspark-lhn-dev"
mkdir -p "$KERNEL_DIR_DEV"
cat > "$KERNEL_DIR_DEV/kernel.json" << EOF
{
  "argv": ["/opt/conda/bin/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "PySpark + lhn-dev (v0.2.0)",
  "language": "python",
  "env": {
    "SPARK_HOME": "/usr/local/spark",
    "HADOOP_CONF_DIR": "/etc/jupyter/configs",
    "PYTHONPATH": "$LHN_PERSIST:$SPARK_CONFIG_PERSIST:/usr/local/spark/python:$PY4J_ZIP:\${PYTHONPATH}",
    "PYSPARK_PYTHON": "python3",
    "PYSPARK_DRIVER_PYTHON": "/opt/conda/bin/python",
    "PYSPARK_SUBMIT_ARGS": "--master yarn --deploy-mode client pyspark-shell"
  }
}
EOF
echo "Created: PySpark + lhn-dev (v0.2.0)"

# Create kernels for upgraded Spark with metastore access
# These use the cloned environments (with newer pyspark if installed) but set HADOOP_CONF_DIR
# to enable metastore connectivity

echo ""
echo "Creating upgraded Spark kernels with metastore access..."

# Upgraded Spark kernel for production environment
KERNEL_DIR_PROD_UPGRADED="$HOME/.local/share/jupyter/kernels/spark-upgraded-prod"
mkdir -p "$KERNEL_DIR_PROD_UPGRADED"
cat > "$KERNEL_DIR_PROD_UPGRADED/kernel.json" << EOF
{
  "argv": ["$PROD_ENV_PATH/bin/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "Spark Upgraded + lhn-prod (Metastore)",
  "language": "python",
  "env": {
    "HADOOP_CONF_DIR": "/etc/jupyter/configs",
    "HADOOP_HOME": "/usr/local/hadoop",
    "JAVA_HOME": "/usr/lib/jvm/java-8-openjdk-amd64/jre/",
    "PYSPARK_SUBMIT_ARGS": "--master yarn --deploy-mode client pyspark-shell",
    "PYSPARK_PYTHON": "$PROD_ENV_PATH/bin/python",
    "PYSPARK_DRIVER_PYTHON": "$PROD_ENV_PATH/bin/python",
    "PATH": "/usr/local/hadoop/bin:\${PATH}"
  }
}
EOF
echo "Created: Spark Upgraded + lhn-prod (Metastore)"

# Upgraded Spark kernel for development environment
KERNEL_DIR_DEV_UPGRADED="$HOME/.local/share/jupyter/kernels/spark-upgraded-dev"
mkdir -p "$KERNEL_DIR_DEV_UPGRADED"
cat > "$KERNEL_DIR_DEV_UPGRADED/kernel.json" << EOF
{
  "argv": ["$DEV_ENV_PATH/bin/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "Spark Upgraded + lhn-dev (Metastore)",
  "language": "python",
  "env": {
    "HADOOP_CONF_DIR": "/etc/jupyter/configs",
    "HADOOP_HOME": "/usr/local/hadoop",
    "JAVA_HOME": "/usr/lib/jvm/java-8-openjdk-amd64/jre/",
    "PYSPARK_SUBMIT_ARGS": "--master yarn --deploy-mode client pyspark-shell",
    "PYSPARK_PYTHON": "$DEV_ENV_PATH/bin/python",
    "PYSPARK_DRIVER_PYTHON": "$DEV_ENV_PATH/bin/python",
    "PATH": "/usr/local/hadoop/bin:\${PATH}"
  }
}
EOF
echo "Created: Spark Upgraded + lhn-dev (Metastore)"

echo ""
echo "These hybrid kernels use the base pyspark (with Hive metastore access)"
echo "but automatically include the lhn paths - no sys.path needed!"
echo ""

echo "========== R Environment =========="
echo ""
echo "  R ENVIRONMENT:"
echo "    Environment: $R_ENV_PATH"
echo "    R Version: 4.4.0"
echo "    Python Version: 3.10"
echo "    Kernels:"
echo "      - Python 3.10 (r_env)  <- For Python ML work"
echo "      - R 4.4.0 (r_env)      <- For R analysis"
echo ""
echo "    Activate: conda activate $R_ENV_PATH"
echo ""
echo "========== Quarto =========="
echo ""
QUARTO_INSTALLED_VERSION=$(quarto --version 2>/dev/null || echo "Not installed")
echo "  Quarto version: ${QUARTO_INSTALLED_VERSION}"
echo "  Location: /opt/quarto/"
echo ""

echo "========== Configuring .bashrc =========="
echo ""

# Initialize miniconda in .bashrc
"$MINICONDA_PATH/bin/conda" init bash 2>/dev/null || true

# Add conda environment activation (only if not already present)
if ! grep -qF "conda activate $R_ENV_PATH" "$HOME/.bashrc"; then
    echo "conda activate $R_ENV_PATH" >> "$HOME/.bashrc"
    echo "Added R environment activation to .bashrc"
fi

# Add aliases for switching between conda environments (only if not already present)
if ! grep -q "alias oldbase=" "$HOME/.bashrc"; then
cat <<'EOF' >> "$HOME/.bashrc"

# === Helpers for switching between conda environments ===
# oldbase: Switch to original Docker conda (base) environment at /opt/conda (has pyspark)
alias oldbase='conda deactivate && source /opt/conda/etc/profile.d/conda.sh && conda activate base && echo "Now using ORIGINAL Docker conda (base) environment from /opt/conda"'
# oldconda: Make original /opt/conda available without activating
alias oldconda='source /opt/conda/etc/profile.d/conda.sh && echo "Original /opt/conda is now available (run conda activate base if you want the base env)"'
EOF
echo "Added conda environment switching aliases (oldbase, oldconda) to .bashrc"
fi

chown "$USER":"$(id -gn)" "$HOME/.bashrc" 2>/dev/null || true  # best-effort; usually not needed when running as $USER

echo "========== List Available Kernels =========="
jupyter kernelspec list 2>/dev/null || echo "(jupyter not in PATH, kernels were registered for --user)"
echo ""
echo "========== Quick Reference =========="
echo ""
echo "  RECOMMENDED KERNELS:"
echo "    PySpark + lhn-dev (v0.2.0)           <- PySpark 2.4.4 + lhn dev (stable metastore)"
echo "    Spark Upgraded + lhn-dev (Metastore) <- Uses lhn_dev env pyspark + metastore"
echo ""
echo "  OTHER KERNELS:"
echo "    Python 3.10 (r_env)  <- For Python ML work (no Spark)"
echo "    R 4.4.0 (r_env)      <- For R analysis"
echo ""
echo "  UPGRADED SPARK NOTE:"
echo "    The 'Spark Upgraded' kernels use HADOOP_CONF_DIR=/etc/jupyter/configs"
echo "    to enable metastore access. If you upgrade pyspark in lhn_prod or lhn_dev,"
echo "    these kernels should connect to the metastore automatically."
echo ""
echo "    To upgrade pyspark in an environment:"
echo "      conda activate $DEV_ENV_PATH"
echo "      pip install pyspark==3.3.0  # or desired version"
echo ""
echo "  Terminal shortcuts:"
echo "    oldbase  - Switch to original Docker conda with pyspark"
echo "    oldconda - Make /opt/conda available without activating"
echo ""
echo "Setup completed at: $(date)"
