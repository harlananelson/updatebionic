#!/bin/bash
# setup-lhn-dual-envs.sh
#
# Purpose: Comprehensive daily container setup including:
#   1. System updates and SSH key restoration
#   2. Quarto installation (system-wide)
#   3. R environment with Python 3.10 and R 4.4.0 (/tmp/r_env)
#   4. Two lhn conda environments for side-by-side testing:
#      - lhn_prod: Production monolithic version (v0.1.0)
#      - lhn_dev:  Development refactored version (v0.2.0-dev)
#
# Prerequisites:
#   - Original Docker conda at /opt/conda with pyspark 2.4.x
#   - Git installed and configured
#   - SSH keys in persistent storage (see Part 1b)
#
# Usage:
#   chmod +x setup-lhn-dual-envs.sh
#   ./setup-lhn-dual-envs.sh
#
# After running, select kernels in JupyterLab:
#   - "PySpark + lhn-prod (v0.1.0)" for production Spark work
#   - "PySpark + lhn-dev (v0.2.0)" for development Spark work
#   - "Python 3.10 (r_env)" for Python ML work
#   - "R 4.4.0 (r_env)" for R analysis

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

# Ensure conda environments registry exists (suppresses "Unable to create environments file" warning)
mkdir -p ~/.conda
touch ~/.conda/environments.txt 2>/dev/null || true

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

# ========== Part 2: System Updates ==========
echo ""
echo "========== Part 2: System Updates =========="

# Update package lists and install system dependencies
echo "Updating apt package lists..."
sudo apt-get update

# Install consolidated system dependencies for geopandas, plotting, and other R packages
# build-essential and gfortran are needed for compiling R packages from source (lobstr, butcher, etc.)
echo "Installing system dependencies..."
sudo apt-get install -y --fix-missing gdal-bin libgdal-dev libgeos-dev libproj-dev libudunits2-dev libfreetype6-dev libpng-dev vim build-essential gfortran

# Update pip in base conda
echo "Updating pip in base conda..."
/opt/conda/bin/python -m pip install --upgrade pip

# ========== Part 3: Install Quarto ==========
echo ""
echo "========== Part 3: Install Quarto =========="

echo "Installing Quarto..."
# Fetch the latest tag from GitHub API
LATEST_TAG=$(curl -s https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
QUARTO_VERSION=${LATEST_TAG#v} # Remove 'v' prefix if present
sudo mkdir -p "/opt/quarto/${QUARTO_VERSION}"
RELEASE_URL="https://github.com/quarto-dev/quarto-cli/releases/download/${LATEST_TAG}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
echo "Downloading and extracting Quarto ${QUARTO_VERSION}..."
sudo curl -L "${RELEASE_URL}" | sudo tar -xz -C "/opt/quarto/${QUARTO_VERSION}" --strip-components=1
sudo ln -sf "/opt/quarto/${QUARTO_VERSION}/bin/quarto" "/usr/local/bin/quarto"
echo "Quarto ${QUARTO_VERSION} installed successfully."

# ========== Part 4: Install Miniconda ==========
echo ""
echo "========== Part 4: Install Miniconda =========="

if [ -d "/tmp/miniconda" ]; then
    echo "Miniconda already installed in /tmp/miniconda. Skipping installation."
else
    echo "Installing Miniconda..."
    # Pin to Miniconda version compatible with GLIBC 2.27 (Ubuntu 18.04)
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-py310_23.11.0-2-Linux-x86_64.sh -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p /tmp/miniconda
    rm /tmp/miniconda.sh
fi

# Set PATH to include Miniconda
export PATH="/tmp/miniconda/bin:$PATH"

# Initialize Conda shell hook for activation in this script
eval "$(conda shell.bash hook)"

# ToS acceptance not required for Miniconda 23.11.0-2 (Ubuntu 18.04 compatible)
echo "Using Miniconda version compatible with Ubuntu 18.04"

# Add channels
echo "Configuring conda channels..."
conda config --add channels conda-forge
conda config --set channel_priority strict

echo "Cleaning conda cache..."
conda clean --all -y

# ========== Part 5: Create R Environment ==========
echo ""
echo "========== Part 5: Create R Environment =========="

R_VERSION="4.4.0"
PYTHON_VERSION="3.10"
R_ENV_PATH="/tmp/r_env"

if [ -d "$R_ENV_PATH" ]; then
    echo "R environment already exists at $R_ENV_PATH. Removing and recreating..."
    conda env remove -p "$R_ENV_PATH" -y 2>/dev/null || rm -rf "$R_ENV_PATH"
fi

echo "Creating R ${R_VERSION} environment with Python ${PYTHON_VERSION}..."
RETRY_COUNT=0
MAX_RETRIES=3
until [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]
do
    conda create -y -p "$R_ENV_PATH" python=${PYTHON_VERSION} r-base=${R_VERSION} cmake && break
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo "Conda environment creation failed. Retrying... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
    sleep 5
done
if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
    echo "ERROR: Conda environment creation failed after $MAX_RETRIES attempts."
    echo "Continuing with lhn setup (R environment will not be available)..."
else
    # Activate R environment for package installation
    conda activate "$R_ENV_PATH"

    # Configure environment variables
    export R_INCLUDE_DIR="$R_ENV_PATH/lib/R/include"
    export R_LIB_PATH="$R_ENV_PATH/lib/R/library"
    export PKG_CONFIG_PATH="$R_ENV_PATH/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

    # Configure .Rprofile
    echo "Configuring .Rprofile..."
    cat <<'EOF' > "$HOME/.Rprofile"
if (.libPaths()[1] != "/tmp/r_env/lib/R/library") {
  .libPaths(c("/tmp/r_env/lib/R/library", .libPaths()))
}
EOF

    # Install Python packages for R environment
    echo "Installing Python packages for R environment..."
    REQUIREMENTS_PYTHON="$SCRIPT_DIR/requirements-python.txt"
    if [[ -f "$REQUIREMENTS_PYTHON" ]]; then
        python -m pip install -r "$REQUIREMENTS_PYTHON"
    else
        echo "Warning: $REQUIREMENTS_PYTHON not found. Installing critical packages..."
        python -m pip install numpy pandas scikit-learn matplotlib seaborn plotnine
    fi

    # Install txtarchive from persistent storage
    TXTARCHIVE_PERSIST="$PERSIST_BASE/txtarchive"
    if [[ -d "$TXTARCHIVE_PERSIST" ]]; then
        echo "Installing txtarchive from $TXTARCHIVE_PERSIST..."
        python -m pip install "$TXTARCHIVE_PERSIST"
    else
        echo "Warning: txtarchive not found at $TXTARCHIVE_PERSIST (skipping)"
    fi

    # Register Python kernel for R environment
    echo "Registering Python 3.10 kernel..."
    python -m pip install ipykernel
    python -m ipykernel install --user --name "python310_renv" --display-name "Python 3.10 (r_env)"

    # Install R packages from conda
    echo "Installing R packages via conda..."
    REQUIREMENTS_R="$SCRIPT_DIR/requirements-R.txt"
    if [[ -f "$REQUIREMENTS_R" ]]; then
        conda install -y -c conda-forge --file "$REQUIREMENTS_R" || echo "Warning: Some R conda packages failed"
    else
        echo "Warning: $REQUIREMENTS_R not found. Installing critical R packages..."
        conda install -y -c conda-forge r-tidyverse r-devtools r-irkernel || echo "Warning: Some R packages failed"
    fi

    # Pre-install RcppTOML via conda (dependency of reticulate)
    echo "Installing RcppTOML via conda-forge..."
    conda install -y -c conda-forge r-rcpptoml || echo "Warning: r-rcpptoml conda install failed"

    # Install R packages via CRAN
    echo "Installing R packages via CRAN..."
    R_PACKAGES_CRAN=("ggsurvfit" "themis" "estimability" "mvtnorm" "numDeriv" "emmeans" "Delta" "vip" "IRkernel" "reticulate" "visNetwork" "config" "sparklyr" "table1" "tableone" "equatiomatic" "svglite" "survRM2" "lobstr" "butcher" "probably" "shades" "ggfittext" "gggenes" "kernelshap")
    R_CRAN_PACKAGES_QUOTED=$(printf "'%s'," "${R_PACKAGES_CRAN[@]}")
    R_CRAN_PACKAGES_QUOTED=${R_CRAN_PACKAGES_QUOTED%,}
    R -e ".libPaths(c('$R_LIB_PATH', .libPaths())); pkgs <- c(${R_CRAN_PACKAGES_QUOTED}); missing_pkgs <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]; if (length(missing_pkgs) > 0) { install.packages(missing_pkgs, lib='$R_LIB_PATH', repos='https://cloud.r-project.org') }"

    # Register R kernel
    echo "Registering R ${R_VERSION} kernel..."
    R -e "IRkernel::installspec(name = 'r_env', displayname = 'R ${R_VERSION} (r_env)')"

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

# Verify pyspark is available in base
echo "Verifying pyspark in base environment..."
conda activate base
python -c "import pyspark; print(f'pyspark version: {pyspark.__version__}')" || {
    echo "ERROR: pyspark not found in base environment"
    exit 1
}
conda deactivate

echo "Prerequisites verified successfully."

# ========== Part 7: Verify/Update Source Repositories ==========
echo ""
echo "========== Part 7: Verify/Update Source Repositories =========="

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

# ========== Part 8: Create Production Environment (v0.1.0) ==========
echo ""
echo "========== Part 8: Create Production Environment (lhn_prod) =========="

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

# ========== Part 9: Create Development Environment (v0.2.0-dev) ==========
echo ""
echo "========== Part 9: Create Development Environment (lhn_dev) =========="

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
    "PYSPARK_PYTHON": "/opt/conda/bin/python",
    "PYSPARK_DRIVER_PYTHON": "/opt/conda/bin/python"
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
    "PYSPARK_PYTHON": "/opt/conda/bin/python",
    "PYSPARK_DRIVER_PYTHON": "/opt/conda/bin/python"
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
echo "    Environment: /tmp/r_env"
echo "    R Version: 4.4.0"
echo "    Python Version: 3.10"
echo "    Kernels:"
echo "      - Python 3.10 (r_env)  <- For Python ML work"
echo "      - R 4.4.0 (r_env)      <- For R analysis"
echo ""
echo "    Activate: conda activate /tmp/r_env"
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
/tmp/miniconda/bin/conda init bash 2>/dev/null || true

# Add conda environment activation (only if not already present)
if ! grep -q "conda activate /tmp/r_env" "$HOME/.bashrc"; then
    echo "conda activate /tmp/r_env" >> "$HOME/.bashrc"
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

sudo chown "$USER":"$(id -gn)" "$HOME/.bashrc"

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
