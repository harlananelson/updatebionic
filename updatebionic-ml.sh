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

set -e
echo "========== Starting daily container setup =========="
date
# Define working directory as the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR"
echo "Using working directory: $WORK_DIR"
# Change to your working directory
cd "$WORK_DIR" || { echo "Directory not found: $WORK_DIR"; exit 1; }
# Export the path to the Python package
export PYTHONPATH="$PYTHONPATH:$WORK_DIR"
echo "========== Part 1: System updates =========="
# Update package lists and install system dependencies if needed
echo "Updating apt package lists..."
sudo apt-get update
# Install consolidated system dependencies for geopandas, plotting, and other R packages
echo "Installing system dependencies..."
sudo apt-get install -y --fix-missing gdal-bin libgdal-dev libgeos-dev libproj-dev libudunits2-dev libfreetype6-dev libpng-dev
# Update pip to the latest version
echo "Updating pip..."
python -m pip install --upgrade pip
# Uninstall any existing versions of py4j to prevent conflicts
echo "Handling py4j package..."
python -m pip uninstall -y py4j || true
echo "========== Part 2: Add python packages to conda environment base in /opt/conda ======"
# Install packages from requirements.txt
echo "Installing Python requirements..."
if [[ -f "$WORK_DIR/requirements.txt" ]]; then
python -m pip install -r "$WORK_DIR/requirements.txt"
else
echo "Warning: requirements.txt not found in $WORK_DIR. Skipping Python package installation from file."
fi

echo "======== Part 3: Install Quarto system wide ================"
# Install Quarto
echo "Installing Quarto..."
# Fetch the latest tag from GitHub API
LATEST_TAG=$(curl -s https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
QUARTO_VERSION=${LATEST_TAG#v} # Remove 'v' prefix if present
sudo mkdir -p "/opt/quarto/${QUARTO_VERSION}"
RELEASE_URL="https://github.com/quarto-dev/quarto-cli/releases/download/${LATEST_TAG}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
echo "Downloading and extracting Quarto ${QUARTO_VERSION}..."
sudo curl -L "${RELEASE_URL}" | sudo tar -xz -C "/opt/quarto/${QUARTO_VERSION}" --strip-components=1
sudo ln -sf "/opt/quarto/${QUARTO_VERSION}/bin/quarto" "/usr/local/bin/quarto"

echo "========== Part 4: R Install Miniconda =========="
# Install and initialize Miniconda in /tmp (fast)
echo "Installing Miniconda..."
if [ -d "/tmp/miniconda" ]; then
echo "Miniconda already installed in /tmp/miniconda. Skipping installation."
else
echo "Miniconda not found. Installing..."
wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
bash /tmp/miniconda.sh -b -p /tmp/miniconda
rm /tmp/miniconda.sh
fi
# Set PATH to include Miniconda
export PATH="/tmp/miniconda/bin:$PATH"
# Initialize Conda shell hook for activation in this script
eval "$(conda shell.bash hook)"
# Accept Anaconda Terms of Service for required channels
echo "Accepting Anaconda Terms of Service..."
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || { echo "Error: Failed to accept ToS for main channel."; exit 1; }
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || { echo "Error: Failed to accept ToS for r channel."; exit 1; }
# Add channels
echo "Adding channels..."
conda config --add channels conda-forge
conda config --set channel_priority strict
echo "Cleaning conda cache to prevent issues with corrupted packages..."
conda clean --all -y

echo "============ Part 5: create Conda environment /tmp/r_env =============="
## Create an R environment with Python and R
# Define R version as a variable for easy updates
R_VERSION="4.5.1"
PYTHON_VERSION="3.10"
# Added definition for R environment path
# Justification: The variable R_ENV_PATH was undefined but used in multiple places (e.g., conda create, environment variables, .libPaths). Defining it here ensures the script runs without errors and maintains consistency with hardcoded paths like in .Rprofile.
R_ENV_PATH="/tmp/r_env"
echo "======= Create and activate conda environment with Python and R ========="

echo "Creating R ${R_VERSION} environment with Python..."
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
echo "Fatal error: Conda environment creation failed after $MAX_RETRIES attempts. Exiting."
exit 1
fi
conda activate "$R_ENV_PATH"
echo "=== Configure environment variables and .Rprofile ========"
export R_INCLUDE_DIR="$R_ENV_PATH/lib/R/include"
export R_LIB_PATH="$R_ENV_PATH/lib/R/library"
export PKG_CONFIG_PATH=/tmp/r_env/lib/pkgconfig:$PKG_CONFIG_PATH
echo "Configuring .Rprofile to prioritize the new R library path..."
cat <<'EOF' > "$HOME/.Rprofile"
if (.libPaths()[1] != "/tmp/r_env/lib/R/library") {
  .libPaths(c("/tmp/r_env/lib/R/library", .libPaths()))
}
EOF
echo "====== Install Python packages using requirements-python.txt ============="
CONDA_PYTHON_PACKAGES="numpy scipy pandas geopandas plotnine lifelines duckdb polars pyogrio pyproj"
conda install -y -c conda-forge $CONDA_PYTHON_PACKAGES
echo " Installing remaining Python packages from requirements-python.txt using pip..."
if [[ -f "$WORK_DIR/requirements-python.txt" ]]; then
python -m pip install -r "$WORK_DIR/requirements-python.txt"
else
echo "Warning: requirements-python.txt not found in $WORK_DIR. Skipping."
fi
echo " ===== Register Python kernel  ==========="
python -m pip install ipykernel
python -m ipykernel install --user --name "python310_renv" --display-name "Python 3.10 (r_env)"
# Now install R packages
# Note: Using conda-forge for packages with system deps/binary needs (via requirements-R.txt), CRAN for pure-R/specialized packages.
# Justification: Filter out r-reticulate from requirements-R.txt to avoid Conda dependency conflicts with r-base=4.5.1. Install reticulate via CRAN instead.
echo " ==== Install R packages from requirements-R.txt ==========="
if [[ -f "$WORK_DIR/requirements-R.txt" ]]; then
grep -v '^r-reticulate$' "$WORK_DIR/requirements-R.txt" > /tmp/requirements-R-filtered.txt
conda install -y -c conda-forge --file /tmp/requirements-R-filtered.txt || { echo "Error: Failed to install R packages from filtered requirements-R.txt."; exit 1; }
rm -f /tmp/requirements-R-filtered.txt
else
echo "Warning: requirements-R.txt not found in $WORK_DIR. Skipping R package installation from file."
fi
echo " ====== Install specified R packages via CRAN that cannot be installed with CONDA ========"
# Correctly format the R_PACKAGES_CRAN array for install.packages()
R_PACKAGES_CRAN=("ggsurvfit" "themis" "estimability" "mvtnorm" "numDeriv" "emmeans" "Delta" "vip" "IRkernel" "reticulate")
R_LIB_PATH="$R_ENV_PATH/lib/R/library"
# A single R -e command to install all remaining packages
R_CRAN_PACKAGES_QUOTED=$(printf "'%s'," "${R_PACKAGES_CRAN[@]}")
R_CRAN_PACKAGES_QUOTED=${R_CRAN_PACKAGES_QUOTED%,} # Remove trailing comma
echo "Installing specified R packages via CRAN if not already present..."
R -e ".libPaths(c('$R_LIB_PATH', .libPaths())); pkgs <- c(${R_CRAN_PACKAGES_QUOTED}); missing_pkgs <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]; if (length(missing_pkgs) > 0) { install.packages(missing_pkgs, lib='$R_LIB_PATH', repos='https://cloud.r-project.org') }"
# Now register the R kernel
echo " ====== Register Jupyter kernel for R =========="
R -e "IRkernel::installspec(name = 'r_env', displayname = 'R ${R_VERSION} (r_env)')"
#
echo "Part 6 ========== Verify installations =========="
# Check py4j version
PY4J_VERSION=$(python -c "import py4j; print(py4j.__version__)" 2>/dev/null || echo "Not installed")
echo "Installed py4j version: ${PY4J_VERSION}"
# Check pyspark version and SPARK_HOME
SPARK_HOME=${SPARK_HOME:-"Not set"}
PYSPARK_VERSION=$(python -c "import pyspark; print(pyspark.__version__)" 2>/dev/null || echo "Not installed")
echo "Installed pyspark version: ${PYSPARK_VERSION}"
echo "SPARK_HOME: ${SPARK_HOME}"
if [ "${PYSPARK_VERSION}" = "Not installed" ]; then
echo "Warning: pyspark not found in current Python path. Ensure base Conda env is activated or paths are set."
fi
# Check Quarto version
QUARTO_INSTALLED_VERSION=$(quarto --version 2>/dev/null || echo "Not installed")
echo "Installed Quarto version: ${QUARTO_INSTALLED_VERSION}"
# Check if plotnine is installed
python -c "import plotnine" 2>/dev/null && echo "plotnine is installed" || echo "plotnine is NOT installed"
# Check R version
echo "R version:"
R --version | head -n1
# Verify Python packages again (after all installations)
echo "Verifying critical Python packages..."
PYTHON_PACKAGES_TO_CHECK=("py4j" "plotnine" "geopandas") # Add other critical packages
for PACKAGE in "${PYTHON_PACKAGES_TO_CHECK[@]}"; do
python -c "import $PACKAGE" 2>/dev/null && echo "$PACKAGE is installed." || echo "$PACKAGE is NOT installed."
done
# Verify R packages again (after all installations)
echo "Verifying critical R packages..."
R_PACKAGES_TO_CHECK_VERIFY=("tidyverse" "IRkernel" "reticulate") # Add other critical R packages
for PACKAGE in "${R_PACKAGES_TO_CHECK_VERIFY[@]}"; do
R -e "if(requireNamespace('$PACKAGE', quietly = TRUE, lib.loc = '$R_LIB_PATH')) {cat('$PACKAGE is installed.\n')} else {cat('$PACKAGE is NOT installed.\n')}"
done
echo "========== Setup complete! =========="
echo "Container is ready for use."
echo "To use R in JupyterLab, choose the 'R ${R_VERSION} (r_env)' kernel."
echo "Setup completed at: $(date)" # SC2005: Replaced echo with just date
echo " Part 7. ====== Modify .bashrc to activate conda environment ==="
echo "Configuring .bashrc with conda init and environment activation..."
conda init bash
echo "conda activate $R_ENV_PATH" >> "$HOME/.bashrc"
sudo chown "$USER":"$(id -gn)" "$HOME/.bashrc"
echo "Part 8 ======  Provide instructions for activating the R environment in the current terminal ======"
echo ""
echo "IMPORTANT: To activate the R environment in your CURRENT terminal session, run:"
echo "source ~/.bashrc"
echo "If you open a new terminal, the environment should activate automatically."