  #!/bin/bash

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
  # Save to: /home/hnelson3/work/Users/hnelson3/daily_setup.sh
  # Make executable with: chmod +x /home/hnelson3/work/Users/hnelson3/daily_setup.sh
  # Run each morning with: /home/hnelson3/work/Users/hnelson3/daily_setup.sh
  # Note: this is run inside a docker container that is hosted on a Ubuntu bionic machine
  # It is designed to not require any modification of the docker script or modification of the system outside the docker container

  # Exit immediately if a command exits with a non-zero status
  set -e

  echo "========== Starting daily container setup =========="
  echo "$(date)"

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

  # Install system dependencies for geopandas (if not already installed)
  echo "Installing system dependencies..."
  sudo apt-get install -y gdal-bin libgdal-dev libgeos-dev libproj-dev

  # Update pip to the latest version
  echo "Updating pip..."
  python -m pip install --upgrade pip

  # Uninstall any existing versions of py4j to prevent conflicts
  echo "Handling py4j package..."
  python -m pip uninstall -y py4j || true

  # Install packages from requirements.txt
  echo "Installing Python requirements..."
  python -m pip install -r $WORK_DIR/requirements.txt

  # Install Quarto
  echo "Installing Quarto..."

  # Fetch the URL for the latest release of Quarto
  RELEASE_URL="https://github.com/quarto-dev/quarto-cli/releases/download/v1.3.450/quarto-1.3.450-linux-amd64.tar.gz"

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
  fi

  # Source conda and add channels
  source /tmp/miniconda/etc/profile.d/conda.sh
  conda config --add channels conda-forge

  # Create and activate conda environment with Python and R
  echo "Creating R 4.3.3 environment with Python..."
  if [ -d "/tmp/r_env" ]; then
    echo "Environment already exists. Skipping creation."
  else
    conda create -y -p /tmp/r_env python r-base=4.3.3 r-irkernel
  fi
  conda activate /tmp/r_env

  # --- BEGIN ADDED LINES TO HANDLE SPARK_HOME CONFLICT ---
  echo "Configuring environment activation for PySpark compatibility..."
  ENV_DIR="/tmp/r_env"
  ACTIVATE_D_DIR="$ENV_DIR/etc/conda/activate.d"
  SPARK_UNSET_SCRIPT="$ACTIVATE_D_DIR/unset_spark_home.sh"

  # Create the activate.d directory if it doesn't exist
  mkdir -p "$ACTIVATE_D_DIR"

  # Create the script to unset SPARK_HOME upon activation
  # This ensures the conda-installed pyspark uses its bundled Spark distribution
  # instead of the system's SPARK_HOME
  echo '#!/bin/bash' > "$SPARK_UNSET_SCRIPT"
  echo 'unset SPARK_HOME' >> "$SPARK_UNSET_SCRIPT"

  # Make the script executable
  chmod +x "$SPARK_UNSET_SCRIPT"
  echo "Added SPARK_HOME unset script to $SPARK_UNSET_SCRIPT"
  # --- END ADDED LINES TO HANDLE SPARK_HOME CONFLICT ---

  # Register the R kernel
  echo "Registering Jupyter kernel..."
  R -e 'if(!("IRkernel" %in% installed.packages())){ install.packages("IRkernel", repos = "https://cloud.r-project.org") }; IRkernel::installspec(name = "r433", displayname = "R 4.3.3")'

  # Install core Python packages using conda-forge first for better dependency management
  echo "Installing core Python packages via conda-forge..."
  # List the packages you want to prioritize installing via conda
  # Include pyspark, py4j, and potentially others known to be well-maintained on conda-forge
  CONDA_PYTHON_PACKAGES="pyspark py4j numpy scipy pandas geopandas plotnine lifelines duckdb polars pyogrio pyproj" # Add others as needed from your requirements

  conda install -y -c conda-forge $CONDA_PYTHON_PACKAGES

  # Install remaining Python packages from requirements-python.txt using pip
  # Pip will handle packages not available via conda and should skip those already installed by conda
  echo "Installing remaining Python packages from requirements-python.txt via pip..."
  if [[ -f "$WORK_DIR/requirements-python.txt" ]]; then
    # NOTE: Using pip here, ensure it installs into the activated conda env /tmp/r_env
    # The --no-deps flag is sometimes used here to prevent pip from reinstalling
    # dependencies already handled by conda, but it can also cause issues.
    # Let's try without --no-deps first, as pip is usually good at skipping.
    python -m pip install -r "$WORK_DIR/requirements-python.txt"
  fi

  echo "Installing R packages from requirements-R.txt using conda..."
  if [[ -f "$WORK_DIR/requirements-R.txt" ]]; then
      conda install -y -c conda-forge --file "$WORK_DIR/requirements-R.txt" || true
      echo "Note: Some R packages may not be available via conda and will be installed via CRAN if needed."
  fi

  # Install R packages not available via conda
  echo "Installing R packages not available via conda..."
  R_PACKAGES=("mapgl" "pdp" "ggsurvfit" "themis" "tidyverse" "estimability" "mvtnorm" "numDeriv" "emmeans")
  for PACKAGE in "${R_PACKAGES[@]}"; do
    echo "Installing $PACKAGE package in R..."
    R -e """
    if(!('$PACKAGE' %in% installed.packages()))
       { install.packages('$PACKAGE', lib='/tmp/r_env/lib/R/library', repos='https://cloud.r-project.org') }
    """
  done

  # Verify R packages
  echo "Verifying R packages..."
  
  for PACKAGE in "${R_PACKAGES[@]}"; do
    R -e """
    if(!('$PACKAGE' %in% installed.packages(lib.loc='/tmp/r_env/lib/R/library'))){
      install.packages('$PACKAGE', lib='/tmp/r_env/lib/R/library', repos='https://cloud.r-project.org')
      cat('Installed $PACKAGE in ', find.package('$PACKAGE'), '\n')
    } else {
      cat('$PACKAGE already installed in ', find.package('$PACKAGE'), '\n')
    }
    """
  done
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
  python -c "import plotnine" 2>/dev/null && echo "plotnine is installed" || echo "plotnine is not installed"

  # Check R version
  echo "R version:"
  R --version | head -n1


  # Activate the conda environment
  conda activate /tmp/r_env

  # Verify Python packages
  echo "Verifying Python packages..."
  PYTHON_PACKAGES_TO_CHECK=("py4j" "plotnine")
  for PACKAGE in "${PYTHON_PACKAGES_TO_CHECK[@]}"; do
    python -c "import $PACKAGE" 2>/dev/null && echo "$PACKAGE is installed" || echo "$PACKAGE is not installed"
  done

  

  echo "========== Setup complete! =========="
  echo "Container is ready for use."
  echo "To use R in JupyterLab, choose the 'R 4.3.3' kernel."
  echo "Setup completed at: $(date)"

  if [ ! -f "$HOME/.bashrc" ]; then
    echo "Creating .bashrc in $HOME"
    touch "$HOME/.bashrc"
    chmod 644 "$HOME/.bashrc"
    chown hnelson3:$(id -gn) "$HOME/.bashrc"
  fi
  grep -q "source /tmp/miniconda/etc/profile.d/conda.sh" "$HOME/.bashrc" || echo "source /tmp/miniconda/etc/profile.d/conda.sh" >> "$HOME/.bashrc"
  grep -q "conda activate /tmp/r_env" "$HOME/.bashrc" || echo "conda activate /tmp/r_env" >> "$HOME/.bashrc"

  # Print a reminder message for conda activation in current terminal
  echo ""
  echo "IMPORTANT: To activate the R environment in your current terminal, run:"
  echo "source /tmp/miniconda/etc/profile.d/conda.sh"
  echo "conda activate /tmp/r_env"
