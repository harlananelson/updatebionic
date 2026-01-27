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
LHN_REPO_URL="https://github.com/harlananelson/lhn.git"

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

# ========== Part 1: Verify Prerequisites ==========
echo ""
echo "========== Part 1: Verify Prerequisites =========="

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

# ========== Part 2: Verify/Update Source Repositories ==========
echo ""
echo "========== Part 2: Verify/Update Source Repositories =========="

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
    CURRENT_BRANCH=$(git branch --show-current)
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

# ========== Part 3: Create Production Environment (v0.1.0) ==========
echo ""
echo "========== Part 3: Create Production Environment (lhn_prod) =========="

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

echo "Installing lhn v0.1.0 (monolithic) in editable mode..."
pip install -e "$LHN_PROD_CLONE"

# Install ipykernel and register
echo "Installing ipykernel..."
pip install ipykernel

echo "Registering Jupyter kernel for production environment..."
python -m ipykernel install --user --name "lhn_prod" --display-name "Python (lhn-prod v0.1.0)"

# Verify installation
echo "Verifying lhn installation..."
python -c "import lhn; print(f'lhn imported successfully')" || echo "WARNING: lhn import failed"

conda deactivate

# ========== Part 4: Create Development Environment (v0.2.0-dev) ==========
echo ""
echo "========== Part 4: Create Development Environment (lhn_dev) =========="

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

echo "Installing dependencies for refactored lhn from persistent storage..."

# Install spark_config_mapper first (required dependency)
echo "Installing spark_config_mapper from $SPARK_CONFIG_PERSIST..."
pip install -e "$SPARK_CONFIG_PERSIST"

# Install omop_concept_mapper (may be required)
if [[ -d "$OMOP_CONCEPT_PERSIST" ]]; then
    echo "Installing omop_concept_mapper from $OMOP_CONCEPT_PERSIST..."
    pip install -e "$OMOP_CONCEPT_PERSIST" || echo "Note: omop_concept_mapper install failed (may not be needed)"
else
    echo "Skipping omop_concept_mapper (not found)"
fi

# Now install lhn v0.2.0-dev from persistent storage
echo "Installing lhn v0.2.0-dev (refactored) from $LHN_PERSIST..."
pip install -e "$LHN_PERSIST"

# Install ipykernel and register
echo "Installing ipykernel..."
pip install ipykernel

echo "Registering Jupyter kernel for development environment..."
python -m ipykernel install --user --name "lhn_dev" --display-name "Python (lhn-dev v0.2.0)"

# Verify installation
echo "Verifying lhn installation..."
python -c "import lhn; print(f'lhn imported successfully')" || echo "WARNING: lhn import failed"

conda deactivate

# ========== Part 5: Summary and Instructions ==========
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
echo "========== List Available Kernels =========="
jupyter kernelspec list 2>/dev/null || echo "(jupyter not in PATH, kernels were registered for --user)"
echo ""
echo "Setup completed at: $(date)"
