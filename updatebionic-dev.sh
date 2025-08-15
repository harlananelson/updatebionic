#!/bin/bash

# This script automates the daily setup process in a Docker container, performing the following tasks:
# 1. Updates system packages and installs dependencies required for GeoPandas.
# 2. Updates pip and installs Python packages from requirements files.
# 3. Installs Quarto CLI.
# 4. Installs and initializes Miniconda in /tmp.
# 5. Sets up an R 4.3.3 and Python Conda environment with necessary packages.
# 6. Registers R and PySpark kernels for JupyterLab.
# 7. Verifies installations.
# 8. Adds commands to .bashrc to activate conda environment in new terminals.
# 9. Provides instructions for activating the environment.

# Save to: ~/your/path/to/updatebionic.sh
# Make executable with: chmod +x ~/your/path/to/updatebionic.sh
# Run with: ./updatebionic.sh
# Note: this is run inside a docker container that is hosted on an Ubuntu bionic machine.
# It is designed to not require any modification of the docker script or modification of the system outside the docker container.

# Exit immediately if a command exits with a non-zero status

# Manually remove pyspark and py4j from your requirements-python.txt file. Let Conda handle these. Your requirements-python.txt should list other Python packages you want to install with pip after the Conda packages are in place.
# Remove pyspark and py4j from your requirements-python.txt and requirements.txt files if they are listed there, as Conda will manage them. The line python -m pip uninstall -y py4j || true can remain to clean up any pre-existing pip versions.

set -e

echo "========== Starting container setup: $(date) =========="

# Define working directory as the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR"

echo "Using working directory: $WORK_DIR"
cd "$WORK_DIR" || { echo "Directory not found: $WORK_DIR"; exit 1; }
export PYTHONPATH="$PYTHONPATH:$WORK_DIR"

echo "========== Part 1: System updates and Quarto installation =========="
sudo apt-get update
echo "Installing system dependencies for GeoPandas..."
sudo apt-get install -y gdal-bin libgdal-dev libgeos-dev libproj-dev

echo "Updating pip..."
python -m pip install --upgrade pip

# Uninstall any existing versions of py4j to prevent conflicts before Conda installs its own
echo "Handling potentially conflicting py4j package..."
python -m pip uninstall -y py4j || true # Continue if not found

# Install packages from requirements.txt (typically non-Conda Python packages)
# Ensure pyspark and py4j are NOT in this file if Conda is handling them.
echo "Installing Python requirements from requirements.txt (if present)..."
if [[ -f "$WORK_DIR/requirements.txt" ]]; then
  python -m pip install -r "$WORK_DIR/requirements.txt"
else
  echo "Warning: requirements.txt not found in $WORK_DIR. Skipping."
fi

echo "Installing Quarto..."
RELEASE_URL="https://github.com/quarto-dev/quarto-cli/releases/download/v1.3.450/quarto-1.3.450-linux-amd64.tar.gz" # Check for latest/desired version
QUARTO_VERSION=$(echo "${RELEASE_URL}" | sed -n 's/.*quarto-\(.*\)-linux-amd64.tar.gz/\1/p')
sudo mkdir -p "/opt/quarto/${QUARTO_VERSION}"
echo "Downloading and extracting Quarto ${QUARTO_VERSION}..."
sudo curl -L "${RELEASE_URL}" | sudo tar -xz -C "/opt/quarto/${QUARTO_VERSION}" --strip-components=1
sudo ln -sf "/opt/quarto/${QUARTO_VERSION}/bin/quarto" "/usr/local/bin/quarto"

echo "========== Part 2: R & Python Conda Environment Setup =========="
echo "Installing Miniconda..."
if [ -d "/tmp/miniconda" ]; then
  echo "Miniconda already installed in /tmp/miniconda. Skipping installation."
else
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -p /tmp/miniconda
  rm /tmp/miniconda.sh
fi

source /tmp/miniconda/etc/profile.d/conda.sh
conda config --add channels conda-forge
conda config --set channel_priority strict

R_ENV_PATH="/tmp/r_env"

echo "Creating Conda environment $R_ENV_PATH with R 4.3.3, Python, and ipykernel..."
if [ -d "$R_ENV_PATH" ]; then
  echo "Conda environment $R_ENV_PATH already exists. Activating."
else
  # r-irkernel for the R kernel, ipykernel for Python/PySpark kernels
  conda create -y -p "$R_ENV_PATH" python r-base=4.3.3 r-irkernel ipykernel
fi
conda activate "$R_ENV_PATH"

echo "Configuring Conda environment activation for PySpark compatibility (unset SPARK_HOME)..."
ENV_DIR="$R_ENV_PATH"
ACTIVATE_D_DIR="$ENV_DIR/etc/conda/activate.d"
SPARK_UNSET_SCRIPT="$ACTIVATE_D_DIR/unset_spark_home.sh"
mkdir -p "$ACTIVATE_D_DIR"
echo '#!/bin/bash' > "$SPARK_UNSET_SCRIPT"
echo 'unset SPARK_HOME' >> "$SPARK_UNSET_SCRIPT"
chmod +x "$SPARK_UNSET_SCRIPT"
echo "Added SPARK_HOME unset script to $SPARK_UNSET_SCRIPT"

echo "Installing core Python packages via conda-forge (including PySpark)..."
# PySpark, py4j, ipykernel are key for this setup. Conda will get the latest compatible PySpark.
CONDA_PYTHON_PACKAGES="pyspark py4j ipykernel numpy scipy pandas geopandas plotnine lifelines duckdb polars pyogrio pyproj"
conda install -y -c conda-forge $CONDA_PYTHON_PACKAGES

# Install remaining Python packages from requirements-python.txt using pip
# Ensure pyspark and py4j are NOT in this file.
echo "Installing additional Python packages from requirements-python.txt via pip (if present)..."
if [[ -f "$WORK_DIR/requirements-python.txt" ]]; then
  python -m pip install -r "$WORK_DIR/requirements-python.txt"
else
  echo "Warning: requirements-python.txt not found in $WORK_DIR. Skipping."
fi

echo "Installing R packages from requirements-R.txt using conda (if present)..."
if [[ -f "$WORK_DIR/requirements-R.txt" ]]; then
    conda install -y -c conda-forge --file "$WORK_DIR/requirements-R.txt" || echo "Note: Some R packages from requirements-R.txt might have failed or are not on Conda. Check CRAN install step."
else
    echo "Warning: requirements-R.txt not found in $WORK_DIR. Skipping Conda R package installation from file."
fi

echo "Installing specified R packages via CRAN if not already present..."
R_PACKAGES_CRAN=("mapgl" "pdp" "ggsurvfit" "themis" "tidyverse" "estimability" "mvtnorm" "numDeriv" "emmeans") # Ensure these are CRAN names
R_LIB_PATH="$R_ENV_PATH/lib/R/library"
for PACKAGE in "${R_PACKAGES_CRAN[@]}"; do
  echo "Checking/Installing CRAN R package: $PACKAGE..."
  R -e "if(!requireNamespace('$PACKAGE', quietly = TRUE, lib.loc = '$R_LIB_PATH')) { install.packages('$PACKAGE', lib='$R_LIB_PATH', repos='https://cloud.r-project.org', Ncpus = parallel::detectCores()) } else { cat('$PACKAGE is already installed.\n')}"
done

echo "========== Registering Jupyter Kernels =========="
# Ensure the conda environment is active
source /tmp/miniconda/etc/profile.d/conda.sh
conda activate "$R_ENV_PATH"

echo "Registering R Jupyter kernel..."
R -e 'if(!requireNamespace("IRkernel", quietly = TRUE)){ install.packages("IRkernel", repos = "https://cloud.r-project.org", Ncpus = parallel::detectCores()) }; IRkernel::installspec(name = "r433_r_env", displayname = "R 4.3.3 (r_env)")'

echo "Registering PySpark Jupyter kernel..."
# This python is from the activated r_env
python -m ipykernel install --user --name "pyspark_r_env" --display-name "PySpark (r_env)"


echo "========== Verifying installations =========="
PY4J_VERSION=$(python -c "import py4j; print(py4j.__version__)" 2>/dev/null || echo "Not installed")
echo "Installed py4j version: ${PY4J_VERSION}"
PYSPARK_VERSION=$(python -c "import pyspark; print(pyspark.__version__)" 2>/dev/null || echo "Not installed")
echo "Installed PySpark version: ${PYSPARK_VERSION}"
QUARTO_INSTALLED_VERSION=$(quarto --version 2>/dev/null || echo "Not installed")
echo "Installed Quarto version: ${QUARTO_INSTALLED_VERSION}"
python -c "import plotnine" 2>/dev/null && echo "plotnine is installed." || echo "plotnine is NOT installed."
echo "R version:"
R --version | head -n1

echo "Verifying critical Python packages..."
PYTHON_PACKAGES_TO_CHECK=("pyspark" "geopandas" "plotnine" "ipykernel")
for PACKAGE in "${PYTHON_PACKAGES_TO_CHECK[@]}"; do
  python -c "import $PACKAGE" 2>/dev/null && echo "$PACKAGE is installed." || echo "$PACKAGE is NOT installed."
done

echo "Verifying critical R packages..."
R_PACKAGES_TO_CHECK_VERIFY=("tidyverse" "IRkernel" "mapgl")
for PACKAGE in "${R_PACKAGES_TO_CHECK_VERIFY[@]}"; do
  R -e "if(requireNamespace('$PACKAGE', quietly = TRUE, lib.loc = '$R_LIB_PATH')) {cat('$PACKAGE is installed.\n')} else {cat('$PACKAGE is NOT installed.\n')}"
done

echo "Listing available Jupyter kernels..."
jupyter kernelspec list

echo "========== Setup complete! $(date) =========="
echo "Container is ready for use."
echo "To use R in JupyterLab, choose the 'R 4.3.3 (r_env)' kernel."
echo "To use PySpark in JupyterLab, choose the 'PySpark (r_env)' kernel."

# Add conda activation to .bashrc if not already present
if [ -f "$HOME/.bashrc" ]; then
  grep -q "source /tmp/miniconda/etc/profile.d/conda.sh" "$HOME/.bashrc" || echo "source /tmp/miniconda/etc/profile.d/conda.sh" >> "$HOME/.bashrc"
  grep -q "conda activate $R_ENV_PATH" "$HOME/.bashrc" || echo "conda activate $R_ENV_PATH" >> "$HOME/.bashrc"
  sudo chown $USER:$(id -gn) "$HOME/.bashrc"
else
  echo "Creating .bashrc in $HOME"
  touch "$HOME/.bashrc"
  echo "source /tmp/miniconda/etc/profile.d/conda.sh" >> "$HOME/.bashrc"
  echo "conda activate $R_ENV_PATH" >> "$HOME/.bashrc"
  sudo chown $USER:$(id -gn) "$HOME/.bashrc"
  chmod 644 "$HOME/.bashrc"
fi

echo ""
echo "IMPORTANT: To activate the environment in your CURRENT terminal session, run:"
echo "source /tmp/miniconda/etc/profile.d/conda.sh"
echo "conda activate $R_ENV_PATH"
echo "New terminals should activate the environment automatically if .bashrc was updated."