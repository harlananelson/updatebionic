#!/bin/bash
# Note to AI modifying this script.
# - Code in this script contains comments explained its purpose do not remove explainations given for existing code
# - Every line of code has a purpose, Do not remove code unless asked even if you determine there is not purpose for the code because you my not have a complete understanding of the code's purpose.
# - When adding or modifying code alway include the purpose for the code in a comment. 
# - If you modify or remove a line, retain the original line as a comment marked as --- IGNORE ---
#
# Note on original system:
# Analysis of the Target Environment
# - Operating System: EC2 instance is running on Ubuntu 18.04.3 LTS (Bionic Beaver)
# - x86_64 system running on an Amazon Linux kernel (amzn2)
# - The / filesystem and /tmp are mounted from a local NVMe disk (/dev/nvme0n1p1), which should be fast.
# - home directory, specifically /home/hnelson3/work, is a FUSE filesystem mounted from s3fs. (slow)
# - Performance Bottleneck: 
#   - Anything installed on th s3fs mount will be slow.  Avoid installation on /home, instead use /tmp
#   - S3fs is not a high-performance filesystem and is particularly bad for I/O-intensive operations like installing software with many small files.
#   - renv installation would be slow because it uses a subdirectory of the project directory, which will be in /home
# default base conda environment with:
#   - in /opt/conda and called base
#   -  R version 4.0.2 and 
#   -  Python 3.7.6 is in /opt/conda and called base 
#   -  pyspark (2.4.x)

# Goal of this script:
## 1. Update the base system such as pip and libraries
#
## 2. Update the /opt/conda base to add the python packages listed in requirements.txt
# - This environment is used with spark in a python jupyter notebook to create analytical datasets
#
## 3. Install quarto system wide ##
#
## 4. Install Miniconda
#
## 5. Create a new conda environment at /tmp/r_env with R and python or R analsysis and ML modeling in python
# - Create and activate conda environment with Python and R
# - Configure environment variables and .Rprofile
# - Install Python packages using requirements-python.txt
# - Register Python kernel
# - Install R packages from requirements-R.txt
# - nstall specified R packages via CRAN that cannot be installed with CONDA
# - Register Jupyter kernel for R
## 6. Verify installations
## 7. Modify .bashrc to activate conda environment
## 8. Provide instructions for activating the R environment in the current terminal.

# - It sets WORK_DIR to the directory containing the script
# - Works even if BASH_SOURCE[0] is empty (e.g., when run via bash directly)

set -euo pipefail

# Script timing - track total execution time
SCRIPT_START_TIME=$SECONDS

# Logging function with timestamps for performance tracking
log_time() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Setup log file for troubleshooting
LOG_DIR="/tmp/bionic-ml-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
exec 2>&1 | tee -a "$LOG_FILE"

log_time "========== Starting daily container setup =========="

# Check for force flag
FORCE_RUN=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_RUN=true
    log_time "Force flag detected - will run full setup"
fi

# State file to track daily runs and avoid redundant work
STATE_FILE="/tmp/.bionic-ml-setup-$(date +%Y%m%d)"
if [[ -f "$STATE_FILE" ]] && [[ "$FORCE_RUN" == false ]]; then
    log_time "Setup already completed today at $(cat $STATE_FILE)"
    log_time "Run with --force to re-execute"
    exit 0
fi

# Fallback to $0 if BASH_SOURCE[0] is empty
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
WORK_DIR="$SCRIPT_DIR"
export WORK_DIR

log_time "Using working directory: $WORK_DIR"
cd "$WORK_DIR" || { log_time "Directory not found: $WORK_DIR"; exit 1; }

# Change to your working directory
cd "$WORK_DIR" || { log_time "Failed to change to directory: $WORK_DIR"; exit 1; }

# Export the path to the Python package
export PYTHONPATH="$PYTHONPATH:$WORK_DIR"

# Use home for conda cache (write once, read many) to speed up daily runs
export CONDA_PKGS_DIRS="$HOME/.conda/pkgs:/tmp/conda-pkgs"
mkdir -p "$HOME/.conda/pkgs" "/tmp/conda-pkgs"

# Utility function for unified package verification
verify_packages() {
    local pkg_type=$1
    shift
    local packages=("$@")
    log_time "Verifying $pkg_type packages..."
    for pkg in "${packages[@]}"; do
        if [[ "$pkg_type" == "python" ]]; then
            python -c "import $pkg" 2>/dev/null && echo "  ✓ $pkg installed" || echo "  ✗ $pkg NOT installed"
        else
            R -q -e "if(requireNamespace('$pkg', quietly=TRUE)) cat('  ✓ $pkg installed\n') else cat('  ✗ $pkg NOT installed\n')" 2>/dev/null
        fi
    done
}

log_time "========== Part 1: System updates =========="
# Update package lists and install system dependencies if needed
log_time "Updating apt package lists..."
sudo apt-get update || { log_time "Failed to update apt packages"; exit 1; }

# Install consolidated system dependencies for geopandas, plotting, and other R packages
log_time "Installing system dependencies..."
sudo apt-get install -y --fix-missing gdal-bin libgdal-dev libgeos-dev libproj-dev libudunits2-dev libfreetype6-dev libpng-dev || \
    { log_time "Failed to install system dependencies"; exit 1; }

# Update pip to the latest version
log_time "Updating pip..."
python -m pip install --upgrade pip || { log_time "Failed to upgrade pip"; exit 1; }

# Uninstall any existing versions of py4j to prevent conflicts
log_time "Handling py4j package..."
python -m pip uninstall -y py4j || true

log_time "========== Part 2: Add python packages to conda environment base in /opt/conda ======"
# Install packages from requirements.txt
log_time "Installing Python requirements..."
if [[ -f "$WORK_DIR/requirements.txt" ]]; then
    python -m pip install -r "$WORK_DIR/requirements.txt" || \
        { log_time "Failed to install Python requirements"; exit 1; }
else
    log_time "Warning: requirements.txt not found in $WORK_DIR. Skipping Python package installation from file."
fi

log_time "======== Part 3: Install Quarto system wide ================"
# Install Quarto
log_time "Installing Quarto..."
# Fetch the latest tag from GitHub API
LATEST_TAG=$(curl -s https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || \
    { log_time "Failed to fetch Quarto version"; exit 1; }
QUARTO_VERSION=${LATEST_TAG#v} # Remove 'v' prefix if present
sudo mkdir -p "/opt/quarto/${QUARTO_VERSION}"
RELEASE_URL="https://github.com/quarto-dev/quarto-cli/releases/download/${LATEST_TAG}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
log_time "Downloading and extracting Quarto ${QUARTO_VERSION}..."
sudo curl -L "${RELEASE_URL}" | sudo tar -xz -C "/opt/quarto/${QUARTO_VERSION}" --strip-components=1 || \
    { log_time "Failed to download/extract Quarto"; exit 1; }
sudo ln -sf "/opt/quarto/${QUARTO_VERSION}/bin/quarto" "/usr/local/bin/quarto"

log_time "========== Part 4: R Install Miniconda =========="
# Install and initialize Miniconda in /tmp (fast)
log_time "Installing Miniconda..."
if [ -d "/tmp/miniconda" ]; then
    log_time "Miniconda already installed in /tmp/miniconda. Skipping installation."
else
    log_time "Miniconda not found. Installing..."
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh || \
        { log_time "Failed to download Miniconda"; exit 1; }
    bash /tmp/miniconda.sh -b -p /tmp/miniconda || \
        { log_time "Failed to install Miniconda"; exit 1; }
    rm /tmp/miniconda.sh
fi

# Set PATH to include Miniconda
export PATH="/tmp/miniconda/bin:$PATH"

# Initialize Conda shell hook for activation in this script
eval "$(conda shell.bash hook)"

# Accept Anaconda Terms of Service for required channels
log_time "Accepting Anaconda Terms of Service..."
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || \
    { log_time "Error: Failed to accept ToS for main channel."; exit 1; }
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || \
    { log_time "Error: Failed to accept ToS for r channel."; exit 1; }

# Add channels
log_time "Adding channels..."
conda config --add channels conda-forge
conda config --set channel_priority strict

log_time "Cleaning conda cache to prevent issues with corrupted packages..."
conda clean --all -y

log_time "============ Part 5: create Conda environment /tmp/r_env =============="
## Create an R environment with Python and R
# Define R version as a variable for easy updates
R_VERSION="4.4.0"
PYTHON_VERSION="3.10"
# Added definition for R environment path
# Justification: The variable R_ENV_PATH was undefined but used in multiple places (e.g., conda create, environment variables, .libPaths). Defining it here ensures the script runs without errors and maintains consistency with hardcoded paths like in .Rprofile.
R_ENV_PATH="/tmp/r_env"

log_time "======= Create and activate conda environment with Python and R ========="
log_time "Creating R ${R_VERSION} environment with Python..."

RETRY_COUNT=0
MAX_RETRIES=3
until [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]
do
    conda create -y -p "$R_ENV_PATH" python=${PYTHON_VERSION} r-base=${R_VERSION} cmake && break
    RETRY_COUNT=$((RETRY_COUNT+1))
    log_time "Conda environment creation failed. Retrying... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
    sleep 5
done

if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
    log_time "Fatal error: Conda environment creation failed after $MAX_RETRIES attempts. Exiting."
    exit 1
fi

conda activate "$R_ENV_PATH"

log_time "=== Configure environment variables and .Rprofile ========"
export R_INCLUDE_DIR="$R_ENV_PATH/lib/R/include"
# --- IGNORE --- export R_LIB_PATH="$R_ENV_PATH/lib/R/library"ß
export R_LIB_PATH="$R_ENV_PATH/lib/R/library"  # Fixed typo: removed ß character
export PKG_CONFIG_PATH="/tmp/r_env/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

log_time "Configuring .Rprofile to prioritize the new R library path..."
cat <<'EOF' > "$HOME/.Rprofile"
if (.libPaths()[1] != "/tmp/r_env/lib/R/library") {
  .libPaths(c("/tmp/r_env/lib/R/library", .libPaths()))
}
EOF

log_time " ===== Install Python packages using requirements-python.txt ============="
log_time "Installing Python packages from requirements-python.txt using pip..."

# Preconditions
REQUIREMENTS_FILE="$WORK_DIR/requirements-python.txt"
REQUIREMENTS_R_FILE="$WORK_DIR/requirements-R.txt"

# Parallel installation of Python and R packages for speed
PYTHON_INSTALL_PID=""
R_INSTALL_PID=""

if [[ -f "$REQUIREMENTS_FILE" ]]; then
    {
        log_time "Starting Python package installation in background..."
        python -m pip install -r "$REQUIREMENTS_FILE" && \
            log_time "Python package installation completed" || \
            log_time "Python package installation failed"
    } &
    PYTHON_INSTALL_PID=$!
else
    log_time "Warning: $REQUIREMENTS_FILE not found. Skipping Python package installation."
fi

log_time " ==== Install R packages from requirements-R.txt ==========="
if [[ -f "$REQUIREMENTS_R_FILE" ]]; then
    {
        log_time "Starting R package installation in background..."
        grep -v '^r-reticulate$' "$REQUIREMENTS_R_FILE" > /tmp/requirements-R-filtered.txt
        conda install -y -c conda-forge --file /tmp/requirements-R-filtered.txt && \
            log_time "R package installation completed" || \
            log_time "R package installation failed"
        rm -f /tmp/requirements-R-filtered.txt
    } &
    R_INSTALL_PID=$!
else
    log_time "Warning: requirements-R.txt not found in $WORK_DIR. Skipping R package installation from file."
fi

# Wait for parallel installations to complete
if [[ -n "$PYTHON_INSTALL_PID" ]]; then
    log_time "Waiting for Python package installation..."
    wait $PYTHON_INSTALL_PID
fi
if [[ -n "$R_INSTALL_PID" ]]; then
    log_time "Waiting for R package installation..."
    wait $R_INSTALL_PID
fi

# ===== Register Python kernel  ===========
log_time "===== Register Python kernel ==========="
python -m pip install ipykernel || { log_time "Failed to install ipykernel"; exit 1; }
python -m ipykernel install --user --name "python310_renv" --display-name "Python 3.10 (r_env)" || \
    { log_time "Failed to register Python kernel"; exit 1; }

# ===== Verify critical Python packages ===========
log_time "===== Verify critical Python packages ==========="
PYTHON_PACKAGES_TO_CHECK=("py4j" "plotnine" "geopandas" "pyogrio" "pyproj")
verify_packages "python" "${PYTHON_PACKAGES_TO_CHECK[@]}"

log_time " ====== Install specified R packages via CRAN that cannot be installed with CONDA ========"
# Correctly format the R_PACKAGES_CRAN array for install.packages()
R_PACKAGES_CRAN=("ggsurvfit" "themis" "estimability" "mvtnorm" "numDeriv" "emmeans" "Delta" "vip" "IRkernel" "reticulate")
R_LIB_PATH="$R_ENV_PATH/lib/R/library"

# A single R -e command to install all remaining packages
R_CRAN_PACKAGES_QUOTED=$(printf "'%s'," "${R_PACKAGES_CRAN[@]}")
R_CRAN_PACKAGES_QUOTED=${R_CRAN_PACKAGES_QUOTED%,} # Remove trailing comma

log_time "Installing specified R packages via CRAN if not already present..."
R -e ".libPaths(c('$R_LIB_PATH', .libPaths())); pkgs <- c(${R_CRAN_PACKAGES_QUOTED}); missing_pkgs <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]; if (length(missing_pkgs) > 0) { install.packages(missing_pkgs, lib='$R_LIB_PATH', repos='https://cloud.r-project.org') }" || \
    { log_time "Warning: Some R packages may have failed to install"; }

# Now register the R kernel
log_time " ====== Register Jupyter kernel for R =========="
R -e "IRkernel::installspec(name = 'r_env', displayname = 'R ${R_VERSION} (r_env)')" || \
    { log_time "Failed to register R kernel"; exit 1; }

log_time "Part 6 ========== Verify installations =========="
# Check py4j version
PY4J_VERSION=$(python -c "import py4j; print(py4j.__version__)" 2>/dev/null || echo "Not installed")
log_time "Installed py4j version: ${PY4J_VERSION}"

# Check Quarto version
QUARTO_INSTALLED_VERSION=$(quarto --version 2>/dev/null || echo "Not installed")
log_time "Installed Quarto version: ${QUARTO_INSTALLED_VERSION}"

# Check if plotnine is installed
python -c "import plotnine" 2>/dev/null && log_time "plotnine is installed" || log_time "plotnine is NOT installed"

# Check R version
log_time "R version:"
R --version | head -n1

# Verify Python packages again (after all installations)
log_time "Final verification of critical Python packages..."
PYTHON_PACKAGES_FINAL=("py4j" "plotnine" "geopandas")
verify_packages "python" "${PYTHON_PACKAGES_FINAL[@]}"

# Verify R packages again (after all installations)
log_time "Final verification of critical R packages..."
R_PACKAGES_FINAL=("tidyverse" "IRkernel" "reticulate")
verify_packages "R" "${R_PACKAGES_FINAL[@]}"

log_time " Part 7. ====== Modify .bashrc to activate conda environment ==="
log_time "Configuring .bashrc with conda init and environment activation..."

# Initialize conda for bash if not already done
conda init bash

# Check if activation line already exists to prevent duplicates
if ! grep -q "conda activate $R_ENV_PATH" "$HOME/.bashrc"; then
    echo "conda activate $R_ENV_PATH" >> "$HOME/.bashrc"
    log_time "Added conda activation to .bashrc"
else
    log_time "Conda activation already present in .bashrc"
fi

sudo chown "$USER":"$(id -gn)" "$HOME/.bashrc"

# Save state file to track completion
date > "$STATE_FILE"

# Calculate and display total execution time
TOTAL_TIME=$((SECONDS - SCRIPT_START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS_REMAINING=$((TOTAL_TIME % 60))

log_time "========== Setup complete! =========="
log_time "Container is ready for use."
log_time "To use R in JupyterLab, choose the 'R ${R_VERSION} (r_env)' kernel."
log_time "Setup completed at: $(date)"
log_time "Total execution time: ${MINUTES}m ${SECONDS_REMAINING}s"
log_time "Log file saved to: $LOG_FILE"

log_time "Part 8 ======  Provide instructions for activating the R environment in the current terminal ======"
echo ""
echo "IMPORTANT: To activate the R environment in your CURRENT terminal session, run:"
echo "source ~/.bashrc"
echo "If you open a new terminal, the environment should activate automatically."
echo ""
echo "To force re-run this setup (ignoring today's state), use: $0 --force"