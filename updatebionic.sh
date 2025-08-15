#!/bin/bash

# This script automates the daily setup process in a Docker container, performing the following tasks:
# 1. Updates system packages and installs dependencies required for GeoPandas.
# 2. Updates pip and installs Python packages from requirements.txt.
# 3. Installs Quarto CLI.
# 4. Installs and initializes Miniconda in /tmp.
# 5. Sets up an R 4.3.3 environment with necessary R packages.
# 6. Registers the R kernel for JupyterLab.
# 7. Installs additional R packages directly in R.
# 8. Verifies the installations of py4j, pyspark, Quarto, plotnine, and R packages.
# 9. Adds commands to .bashrc to activate conda environment in new terminals.
# 10. Provides instructions for activating the R environment in the current terminal.

# Daily setup script for Docker container
# Combines Quarto installation and R environment setup
# Save to: ~/your/path/to/daily_setup.sh
# Make executable with: chmod +x ~/your/path/to/daily_setup.sh
# Run each morning with: ~/your/path/to/daily_setup.sh
# Note: this is run inside a docker container that is hosted on a Ubuntu bionic machine
# It is designed to not require any modification of the docker script or modification of the system outside the docker container

# Exit immediately if a command exits with a non-zero status
set -e

echo "========== Starting daily container setup =========="
date # SC2005: Useless echo? Instead of 'echo $(cmd)', just use 'cmd'.

# Define working directory as the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR"

echo "Using working directory: $WORK_DIR"

# Change to your working directory
cd "$WORK_DIR" || { echo "Directory not found: $WORK_DIR"; exit 1; }

# Export the path to the Python package
export PYTHONPATH="$PYTHONPATH:$WORK_DIR"

echo "========== Part 1: System updates and Quarto installation =========="

# Update package lists and install system dependencies if needed
echo "Updating apt package lists..."
sudo apt-get update

# Install system dependencies for geopandas and other R packages
echo "Installing system dependencies..."
sudo apt-get install -y --fix-missing gdal-bin libgdal-dev libgeos-dev libproj-dev libudunits2-dev

# Install system dependencies for geopandas (if not already installed)
echo "Installing system dependencies..."
sudo apt-get install -y --fix-missing gdal-bin libgdal-dev libgeos-dev libproj-dev
# sudo apt-get install -y gdal-bin libgdal-dev libgeos-dev libproj-dev

# Update pip to the latest version
echo "Updating pip..."
python -m pip install --upgrade pip

# Uninstall any existing versions of py4j to prevent conflicts
echo "Handling py4j package..."
python -m pip uninstall -y py4j || true

# Install packages from requirements.txt
echo "Installing Python requirements..."
# Ensure requirements.txt is in the same directory as the script, or provide a full path
if [[ -f "$WORK_DIR/requirements.txt" ]]; then
  python -m pip install -r "$WORK_DIR/requirements.txt"
else
  echo "Warning: requirements.txt not found in $WORK_DIR. Skipping Python package installation from file."
fi

# Install Quarto
echo "Installing Quarto..."

# Fetch the URL for the latest release of Quarto (or a specific version)
RELEASE_URL="https://github.com/quarto-dev/quarto-cli/releases/download/v1.3.450/quarto-1.3.450-linux-amd64.tar.gz" # You can update this URL to a specific version if needed

# Extract the version number from the URL
QUARTO_VERSION=$(echo "${RELEASE_URL}" | sed -n 's/.*quarto-\(.*\)-linux-amd64.tar.gz/\1/p')

# Create the directory for the specific version
sudo mkdir -p "/opt/quarto/${QUARTO_VERSION}"

# Download and extract Quarto
echo "Downloading and extracting Quarto ${QUARTO_VERSION}..."
sudo curl -L "${RELEASE_URL}" | sudo tar -xz -C "/opt/quarto/${QUARTO_VERSION}" --strip-components=1

# Create symlink
sudo ln -sf "/opt/quarto/${QUARTO_VERSION}/bin/quarto" "/usr/local/bin/quarto"

echo "========== Part 2: R environment setup =========="

# Install and initialize Miniconda in /tmp (fast)
echo "Installing Miniconda..."
if [ -d "/tmp/miniconda" ]; then
  echo "Miniconda already installed in /tmp/miniconda. Skipping installation."
else
  echo "Miniconda not found. Installing..."
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -p /tmp/miniconda
  rm /tmp/miniconda.sh # Clean up installer
fi

# Source conda and add channels
# shellcheck source=/dev/null
source /tmp/miniconda/etc/profile.d/conda.sh # SC1091 can be ignored here as file is created at runtime
conda config --add channels conda-forge
conda config --set channel_priority strict # Recommended for better dependency resolution

echo "Cleaning conda cache to prevent issues with corrupted packages..."
conda clean --all -y

# Define the R environment path
R_ENV_PATH="/tmp/r_env"

# If the R environment directory exists from a previous run, remove it to ensure a clean state and correct permissions
if [ -d "$R_ENV_PATH" ]; then
  echo "Removing existing Conda environment $R_ENV_PATH for a clean setup..."
  # Use sudo to remove, as the directory might be owned by root or another user
  if ! sudo rm -rf "$R_ENV_PATH"; then # SC2181: Check exit code directly
    echo "Error: Failed to remove existing environment $R_ENV_PATH. Please check permissions or remove manually."
    exit 1
  fi
fi

# Create and activate conda environment with Python and R
echo "Creating R 4.3.3 environment with Python..."
conda create -y -p "$R_ENV_PATH" python=3.10 r-base=4.3.3 r-irkernel
conda activate "$R_ENV_PATH"

# --- BEGIN ADDED LINES TO HANDLE SPARK_HOME CONFLICT ---
echo "Configuring environment activation for PySpark compatibility..."
ENV_DIR="$R_ENV_PATH"
ACTIVATE_D_DIR="$ENV_DIR/etc/conda/activate.d"
SPARK_UNSET_SCRIPT="$ACTIVATE_D_DIR/unset_spark_home.sh"

# Create the activate.d directory if it doesn't exist
mkdir -p "$ACTIVATE_D_DIR"

# Create the script to unset SPARK_HOME upon activation
echo '#!/bin/bash' > "$SPARK_UNSET_SCRIPT"
echo 'unset SPARK_HOME' >> "$SPARK_UNSET_SCRIPT"

# Make the script executable
chmod +x "$SPARK_UNSET_SCRIPT"
echo "Added SPARK_HOME unset script to $SPARK_UNSET_SCRIPT"
# --- END ADDED LINES TO HANDLE SPARK_HOME CONFLICT ---

# Register the R kernel
echo "Registering Jupyter kernel..."
R -e 'if(!requireNamespace("IRkernel", quietly = TRUE)){ install.packages("IRkernel", repos = "https://cloud.r-project.org") }; IRkernel::installspec(name = "r433", displayname = "R 4.3.3")'


# Install core Python packages using conda-forge first for better dependency management
echo "Installing core Python packages via conda-forge..."
# List the packages you want to prioritize installing via conda
CONDA_PYTHON_PACKAGES="numpy scipy pandas geopandas plotnine lifelines duckdb polars pyogrio pyproj"
conda install -y -c conda-forge $CONDA_PYTHON_PACKAGES

# Install remaining Python packages from requirements-python.txt using pip
# Pip will handle packages not available via conda and should skip those already installed by conda
echo "Installing remaining Python packages from requirements-python.txt via pip..."
if [[ -f "$WORK_DIR/requirements-python.txt" ]]; then
  python -m pip install -r "$WORK_DIR/requirements-python.txt"
else
  echo "Warning: requirements-python.txt not found in $WORK_DIR. Skipping."
fi

# Register Python kernel for the r_env environment (after packages are installed)
echo "Registering Python 3.10 kernel..."
python -m pip install ipykernel
python -m ipykernel install --user --name "python310_renv" --display-name "Python 3.10 (r_env)"

echo "Installing R packages from requirements-R.txt using conda..."
if [[ -f "$WORK_DIR/requirements-R.txt" ]]; then
    # Attempt to install R packages listed in requirements-R.txt via conda
    # Format of requirements-R.txt should be one package per line, e.g., r-ggplot2
    conda install -y -c conda-forge --file "$WORK_DIR/requirements-R.txt" || echo "Note: Some R packages from requirements-R.txt might not be available via conda or failed to install. They may need to be installed via CRAN."
else
    echo "Warning: requirements-R.txt not found in $WORK_DIR. Skipping R package installation from file."
fi

# Install R packages not available via conda or if requirements-R.txt is not used/sufficient
echo "Installing specified R packages via CRAN if not already present..."
R_PACKAGES_CRAN=("mapgl" "pdp" "ggsurvfit" "themis" "tidyverse" "estimability" "mvtnorm" "numDeriv" "emmeans") # Ensure these are CRAN names
R_LIB_PATH="$R_ENV_PATH/lib/R/library" # Install into the conda environment's R library

# THIS IS A LIKELY AREA FOR LINE 192.
# If the error is here, check the R_PACKAGES_CRAN definition above for typos (e.g. spaces around =)
# Also, add 'set -x' before this loop and 'set +x' after to debug.
for PACKAGE in "${R_PACKAGES_CRAN[@]}"; do
  echo "Checking/Installing $PACKAGE package in R..."
  R -e "if(!requireNamespace('$PACKAGE', quietly = TRUE, lib.loc = '$R_LIB_PATH')) { install.packages('$PACKAGE', lib='$R_LIB_PATH', repos='https://cloud.r-project.org') } else { cat('$PACKAGE is already installed.\n')}"
done


# Set R environment variables to prioritize the new library path
echo "Configuring .Rprofile to prioritize the new R library path..."
echo "if (.libPaths()[1] != \"/tmp/r_env/lib/R/library\") {" >> /home/hnelson3/.Rprofile
echo "  .libPaths(c(\"/tmp/r_env/lib/R/library\", .libPaths()))" >> /home/hnelson3/.Rprofile
echo "}" >> /home/hnelson3/.Rprofile


echo "========== Verifying installations =========="

# Check py4j version
PY4J_VERSION=$(python -c "import py4j; print(py4j.__version__)" 2>/dev/null || echo "Not installed")
echo "Installed py4j version: ${PY4J_VERSION}"

# Check pyspark version
PYSPARK_VERSION=$(python -c "import pyspark; print(pyspark.__version__)" 2>/dev/null || echo "Not installed")
echo "Installed pyspark version: ${PYSPARK_VERSION}"

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
R_PACKAGES_TO_CHECK_VERIFY=("tidyverse" "IRkernel" "mapgl") # Add other critical R packages
for PACKAGE in "${R_PACKAGES_TO_CHECK_VERIFY[@]}"; do
  R -e "if(requireNamespace('$PACKAGE', quietly = TRUE, lib.loc = '$R_LIB_PATH')) {cat('$PACKAGE is installed.\n')} else {cat('$PACKAGE is NOT installed.\n')}"
done

echo "========== Setup complete! =========="
echo "Container is ready for use."
echo "To use R in JupyterLab, choose the 'R 4.3.3' kernel."
echo "Setup completed at: $(date)" # SC2005: Replaced echo with just date

# Add conda activation to .bashrc if not already present
# This ensures the environment is activated in new terminal sessions
if [ -f "$HOME/.bashrc" ]; then
  grep -q "source /tmp/miniconda/etc/profile.d/conda.sh" "$HOME/.bashrc" || echo "source /tmp/miniconda/etc/profile.d/conda.sh" >> "$HOME/.bashrc"
  grep -q "conda activate $R_ENV_PATH" "$HOME/.bashrc" || echo "conda activate $R_ENV_PATH" >> "$HOME/.bashrc"
  # Update ownership of .bashrc to the current user and their primary group
  sudo chown "$USER":"$(id -gn)" "$HOME/.bashrc" # SC2086 & SC2046
else
  echo "Creating .bashrc in $HOME"
  touch "$HOME/.bashrc"
  echo "source /tmp/miniconda/etc/profile.d/conda.sh" >> "$HOME/.bashrc"
  echo "conda activate $R_ENV_PATH" >> "$HOME/.bashrc"
  sudo chown "$USER":"$(id -gn)" "$HOME/.bashrc" # SC2086 & SC2046
  chmod 644 "$HOME/.bashrc"
fi


# Print a reminder message for conda activation in current terminal
echo ""
echo "IMPORTANT: To activate the R environment in your CURRENT terminal session, run:"
echo "source /tmp/miniconda/etc/profile.d/conda.sh"
echo "conda activate $R_ENV_PATH"
echo "If you open a new terminal, the environment should activate automatically if .bashrc was updated."

