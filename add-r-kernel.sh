#!/bin/bash
# add-r-kernel.sh
#
# Purpose: Add R environment and kernel to an existing container setup
# Creates /tmp/r_env with R 4.4.0 + Python 3.10 and registers Jupyter kernels
#
# Usage:
#   chmod +x add-r-kernel.sh
#   ./add-r-kernel.sh
#
# After running, select kernels in JupyterLab:
#   - "Python 3.10 (r_env)" for Python ML work
#   - "R 4.4.0 (r_env)" for R analysis

set -eo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

echo "========== Add R Kernel Setup =========="
date

# ========== Part 1: Install Miniconda (if needed) ==========
echo ""
echo "========== Part 1: Install Miniconda =========="

if [ -d "/tmp/miniconda" ]; then
    echo "Miniconda already installed in /tmp/miniconda."
else
    echo "Installing Miniconda..."
    # Pin to Miniconda version compatible with GLIBC 2.27 (Ubuntu 18.04)
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-py310_23.11.0-2-Linux-x86_64.sh -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p /tmp/miniconda
    rm /tmp/miniconda.sh
fi

# Set PATH to include Miniconda
export PATH="/tmp/miniconda/bin:$PATH"

# Initialize Conda shell hook
eval "$(conda shell.bash hook)"

# Configure channels
echo "Configuring conda channels..."
conda config --add channels conda-forge 2>/dev/null || true
conda config --set channel_priority strict

# ========== Part 2: Create R Environment ==========
echo ""
echo "========== Part 2: Create R Environment =========="

R_VERSION="4.4.0"
PYTHON_VERSION="3.10"
R_ENV_PATH="/tmp/r_env"
R_LIB_PATH="$R_ENV_PATH/lib/R/library"

if [ -d "$R_ENV_PATH" ]; then
    echo "R environment already exists at $R_ENV_PATH."
    read -p "Remove and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing environment..."
        conda env remove -p "$R_ENV_PATH" -y 2>/dev/null || rm -rf "$R_ENV_PATH"
    else
        echo "Keeping existing environment. Activating..."
        conda activate "$R_ENV_PATH"
        echo "Environment activated. Skipping to kernel registration."

        # Just ensure kernels are registered
        echo "Ensuring kernels are registered..."
        python -m pip install ipykernel -q
        python -m ipykernel install --user --name "python310_renv" --display-name "Python 3.10 (r_env)"
        R -e "IRkernel::installspec(name = 'r_env', displayname = 'R ${R_VERSION} (r_env)')" 2>/dev/null || true

        echo ""
        echo "Done! Kernels should be available in JupyterLab."
        exit 0
    fi
fi

echo "Creating R ${R_VERSION} environment with Python ${PYTHON_VERSION}..."
echo "This may take several minutes..."

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
    exit 1
fi

# Activate R environment
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

# ========== Part 3: Install Python Packages ==========
echo ""
echo "========== Part 3: Install Python Packages =========="

REQUIREMENTS_PYTHON="$SCRIPT_DIR/requirements-python.txt"
if [[ -f "$REQUIREMENTS_PYTHON" ]]; then
    echo "Installing from $REQUIREMENTS_PYTHON..."
    python -m pip install -r "$REQUIREMENTS_PYTHON"
else
    echo "requirements-python.txt not found. Installing critical packages..."
    python -m pip install numpy pandas scikit-learn matplotlib seaborn plotnine lifelines
fi

# Register Python kernel
echo "Registering Python 3.10 kernel..."
python -m pip install ipykernel
python -m ipykernel install --user --name "python310_renv" --display-name "Python 3.10 (r_env)"

# ========== Part 4: Install R Packages ==========
echo ""
echo "========== Part 4: Install R Packages =========="

# Install R packages from conda
REQUIREMENTS_R="$SCRIPT_DIR/requirements-R.txt"
if [[ -f "$REQUIREMENTS_R" ]]; then
    echo "Installing R packages from $REQUIREMENTS_R via conda..."
    conda install -y -c conda-forge --file "$REQUIREMENTS_R" || echo "Warning: Some R conda packages failed"
else
    echo "requirements-R.txt not found. Installing critical R packages..."
    conda install -y -c conda-forge r-tidyverse r-devtools r-irkernel || echo "Warning: Some R packages failed"
fi

# Pre-install RcppTOML via conda (dependency of reticulate)
echo "Installing RcppTOML via conda-forge..."
conda install -y -c conda-forge r-rcpptoml || echo "Warning: r-rcpptoml conda install failed"

# Install R packages via CRAN
echo "Installing R packages via CRAN (this may take a while)..."
R_PACKAGES_CRAN=("ggsurvfit" "themis" "estimability" "mvtnorm" "numDeriv" "emmeans" "Delta" "vip" "IRkernel" "reticulate" "visNetwork" "config" "sparklyr" "table1" "tableone" "equatiomatic" "svglite" "survRM2")
R_CRAN_PACKAGES_QUOTED=$(printf "'%s'," "${R_PACKAGES_CRAN[@]}")
R_CRAN_PACKAGES_QUOTED=${R_CRAN_PACKAGES_QUOTED%,}
R -e ".libPaths(c('$R_LIB_PATH', .libPaths())); pkgs <- c(${R_CRAN_PACKAGES_QUOTED}); missing_pkgs <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]; if (length(missing_pkgs) > 0) { install.packages(missing_pkgs, lib='$R_LIB_PATH', repos='https://cloud.r-project.org') }"

# Register R kernel
echo "Registering R ${R_VERSION} kernel..."
R -e "IRkernel::installspec(name = 'r_env', displayname = 'R ${R_VERSION} (r_env)')"

# ========== Part 5: Verify and Summary ==========
echo ""
echo "========== Setup Complete! =========="
echo ""
echo "R Environment created at: $R_ENV_PATH"
echo ""
echo "Available Kernels:"
echo "  - Python 3.10 (r_env)  <- For Python ML work"
echo "  - R 4.4.0 (r_env)      <- For R analysis"
echo ""
echo "To activate in terminal:"
echo "  source /tmp/miniconda/bin/activate /tmp/r_env"
echo ""
echo "Verifying installations..."
echo ""
echo "Python version:"
python --version
echo ""
echo "R version:"
R --version | head -n1
echo ""
echo "Checking critical packages..."
python -c "import pandas; print(f'pandas: {pandas.__version__}')" 2>/dev/null || echo "pandas: NOT installed"
python -c "import sklearn; print(f'scikit-learn: {sklearn.__version__}')" 2>/dev/null || echo "scikit-learn: NOT installed"
R -e "packageVersion('tidyverse')" 2>/dev/null | grep -o '\[1\].*' || echo "tidyverse: checking..."
echo ""
echo "Setup completed at: $(date)"
echo ""
echo "Refresh your JupyterLab browser to see the new kernels!"
