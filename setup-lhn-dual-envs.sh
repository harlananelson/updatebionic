#!/bin/bash
# setup-lhn-dual-envs.sh
#
# Purpose: Create two conda environments for side-by-side testing of lhn versions
#   - lhn_prod: Production monolithic version (v0.1.0)
#   - lhn_dev:  Development refactored version (v0.2.0-dev)
#
# Prerequisites:
#   - Original Docker conda at /opt/conda with pyspark 2.4.x
#   - Git installed and configured
#
# Usage:
#   chmod +x setup-lhn-dual-envs.sh
#   ./setup-lhn-dual-envs.sh
#
# After running, select kernels in JupyterLab:
#   - "Python (lhn-prod v0.1.0)" for production testing
#   - "Python (lhn-dev v0.2.0)" for development testing

# Note: Not using -u (nounset) because conda activation scripts have unbound variables
set -eo pipefail

# Configuration
# Using SSH URL (more reliable for git operations)
LHN_REPO_URL="git@github.com:harlananelson/lhn.git"

# Persistent storage paths (S3 mount - slow but survives container restart)
PERSIST_BASE="$HOME/work/Users/hnelson3"
LHN_PERSIST="$PERSIST_BASE/lhn"
SPARK_CONFIG_PERSIST="$PERSIST_BASE/spark_config_mapper"
OMOP_CONCEPT_PERSIST="$PERSIST_BASE/omop_concept_mapper"

# Temporary paths (fast local disk - wiped on container restart)
LHN_PROD_CLONE="/tmp/lhn_prod_src"   # Clone for production (v0.1.0-monolithic)

# Conda environment paths (fast local disk)
PROD_ENV_PATH="/tmp/lhn_prod"
DEV_ENV_PATH="/tmp/lhn_dev"
OLD_CONDA_PATH="/opt/conda"

# Fallback to $0 if BASH_SOURCE[0] is empty
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

echo "========== LHN Dual Environment Setup =========="
echo "Script directory: $SCRIPT_DIR"
date

# ========== Part 1: Install SSH and Restore Keys ==========
echo ""
echo "========== Part 1: Install SSH and Restore Keys =========="

# Install openssh-client if not available
if ! command -v ssh &> /dev/null; then
    echo "Installing openssh-client..."
    sudo apt-get update
    sudo apt-get install -y openssh-client
fi

# Create ~/.ssh directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Persistent SSH key storage location
SSH_PERSIST_DIR="$HOME/work/Users/hnelson3/.ssh"

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
    echo "Adding SSH key to agent (you'll be prompted for passphrase once)..."
    ssh-add ~/.ssh/id_ed25519

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

# ========== Part 2: Verify Prerequisites ==========
echo ""
echo "========== Part 2: Verify Prerequisites =========="

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

# Verify pyspark is available in base
echo "Verifying pyspark in base environment..."
conda activate base
python -c "import pyspark; print(f'pyspark version: {pyspark.__version__}')" || {
    echo "ERROR: pyspark not found in base environment"
    exit 1
}
conda deactivate

echo "Prerequisites verified successfully."

# ========== Part 3: Verify/Update Source Repositories ==========
echo ""
echo "========== Part 3: Verify/Update Source Repositories =========="

# --- Production: Clone lhn to /tmp with v0.1.0-monolithic branch ---
echo ""
echo "--- Setting up PRODUCTION source (v0.1.0-monolithic) ---"
if [[ -d "$LHN_PROD_CLONE" ]]; then
    echo "Removing existing production clone at $LHN_PROD_CLONE..."
    rm -rf "$LHN_PROD_CLONE"
fi

echo "Cloning lhn repository for production to /tmp (fast)..."
git clone "$LHN_REPO_URL" "$LHN_PROD_CLONE"
cd "$LHN_PROD_CLONE"
git fetch --all --tags
git checkout v0.1.0-monolithic
echo "Production clone checked out to v0.1.0-monolithic"
echo "Available tags:"
git tag -l

# --- Development: Use existing persistent directories ---
echo ""
echo "--- Verifying DEVELOPMENT sources (persistent storage) ---"

# Verify lhn exists and is on main branch
if [[ -d "$LHN_PERSIST" ]]; then
    echo "Found lhn at $LHN_PERSIST"
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
    echo "ERROR: lhn not found at $LHN_PERSIST"
    echo "Please clone it first: git clone $LHN_REPO_URL $LHN_PERSIST"
    exit 1
fi

# Verify spark_config_mapper exists
if [[ -d "$SPARK_CONFIG_PERSIST" ]]; then
    echo "Found spark_config_mapper at $SPARK_CONFIG_PERSIST"
    cd "$SPARK_CONFIG_PERSIST"
    git pull origin main 2>/dev/null || echo "  (pull skipped or failed)"
else
    echo "ERROR: spark_config_mapper not found at $SPARK_CONFIG_PERSIST"
    exit 1
fi

# Verify omop_concept_mapper exists
if [[ -d "$OMOP_CONCEPT_PERSIST" ]]; then
    echo "Found omop_concept_mapper at $OMOP_CONCEPT_PERSIST"
    cd "$OMOP_CONCEPT_PERSIST"
    git pull origin main 2>/dev/null || echo "  (pull skipped or failed)"
else
    echo "WARNING: omop_concept_mapper not found at $OMOP_CONCEPT_PERSIST"
    echo "Will skip installation (may not be required)"
fi

echo ""
echo "Source repositories ready."

# ========== Part 4: Create Production Environment (v0.1.0) ==========
echo ""
echo "========== Part 4: Create Production Environment (lhn_prod) =========="

# Remove existing environment if present
if [[ -d "$PROD_ENV_PATH" ]]; then
    echo "Removing existing production environment..."
    conda env remove -p "$PROD_ENV_PATH" -y 2>/dev/null || rm -rf "$PROD_ENV_PATH"
fi

# Clone the base environment
echo "Cloning base environment to $PROD_ENV_PATH..."
echo "This may take a few minutes..."
conda create -p "$PROD_ENV_PATH" --clone base -y

# Activate and install lhn v0.1.0
echo "Activating production environment..."
conda activate "$PROD_ENV_PATH"

# Upgrade pip to avoid build isolation issues that can corrupt packages
# Old pip (20.0.2) has issues with build isolation that can corrupt pandas
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

# Install ipykernel and register
echo "Installing ipykernel..."
pip install ipykernel

echo "Registering Jupyter kernel for production environment..."
python -m ipykernel install --user --name "lhn_prod" --display-name "Python (lhn-prod v0.1.0)"

# Verify installation
echo "Verifying lhn installation..."
python -c "import lhn; print(f'lhn imported successfully')" || echo "WARNING: lhn import failed"

conda deactivate

# ========== Part 5: Create Development Environment (v0.2.0-dev) ==========
echo ""
echo "========== Part 5: Create Development Environment (lhn_dev) =========="

# Remove existing environment if present
if [[ -d "$DEV_ENV_PATH" ]]; then
    echo "Removing existing development environment..."
    conda env remove -p "$DEV_ENV_PATH" -y 2>/dev/null || rm -rf "$DEV_ENV_PATH"
fi

# Clone the base environment
echo "Cloning base environment to $DEV_ENV_PATH..."
echo "This may take a few minutes..."
conda create -p "$DEV_ENV_PATH" --clone base -y

# Activate and install lhn v0.2.0-dev
echo "Activating development environment..."
conda activate "$DEV_ENV_PATH"

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

# Install ipykernel and register
echo "Installing ipykernel..."
pip install ipykernel

echo "Registering Jupyter kernel for development environment..."
python -m ipykernel install --user --name "lhn_dev" --display-name "Python (lhn-dev v0.2.0)"

# Verify installation
echo "Verifying lhn installation..."
python -c "import lhn; print(f'lhn imported successfully')" || echo "WARNING: lhn import failed"

conda deactivate

# ========== Part 6: Summary and Instructions ==========
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
echo "In JupyterLab, create two notebooks and select:"
echo "  - Notebook 1: Kernel > Change Kernel > Python (lhn-prod v0.1.0)"
echo "  - Notebook 2: Kernel > Change Kernel > Python (lhn-dev v0.2.0)"
echo ""
echo "Run cells step-by-step in both to compare behavior."
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
echo "========== List Available Kernels =========="
jupyter kernelspec list 2>/dev/null || echo "(jupyter not in PATH, kernels were registered for --user)"
echo ""
echo "Setup completed at: $(date)"
