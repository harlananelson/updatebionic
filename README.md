# Ubuntu Bionic Data Science Environment Setup (`updatebionic`)

This repository provides a shell script (`updatebionic.sh`) designed to automate the setup of a comprehensive data science environment, particularly within a Docker container running on an Ubuntu Bionic (18.04 LTS) host. It installs and configures Quarto, R, Python (via Miniconda), and numerous essential data science packages for both languages.

## Use Case & Motivation

This script is ideal for data scientists and researchers who:

* Work within Docker containers (or fresh Ubuntu Bionic VMs/systems) and need a consistent, reproducible environment.
* Require a specific version of R (4.3.3 in this script) alongside Python.
* Utilize Quarto for reproducible reports and presentations.
* Need a broad range of common data science libraries for R and Python, including those for geospatial analysis, machine learning, data manipulation, and visualization.
* Want to ensure compatibility between PySpark and a system-installed Spark (by unsetting `SPARK_HOME` within the Conda environment).
* Prefer to manage Python and R environments primarily through Conda but also need to install packages directly from CRAN or PyPI.

The primary motivation is to simplify and accelerate the "daily setup" or initial configuration of a development environment, ensuring all necessary tools and packages are installed and correctly configured with minimal manual intervention. This is particularly useful for ephemeral environments like Docker containers that might be reset frequently.

## Features

* **System Updates:** Updates `apt` package lists.
* **Geospatial Dependencies:** Installs system libraries required for packages like GeoPandas (`gdal-bin`, `libgdal-dev`, etc.).
* **Python Environment:**
    * Updates `pip`.
    * Installs Python packages from `requirements.txt` (primary list, potentially for `pip`) and `requirements-python.txt` (more comprehensive list, attempted with `pip` after Conda).
    * Installs core Python packages (like `pyspark`, `geopandas`, `pandas`, `numpy`) via Conda for robust dependency management.
* **Quarto Installation:** Downloads and installs a specific version of Quarto CLI (v1.3.450) to `/opt/quarto` and creates a symlink to `/usr/local/bin/quarto`.
* **Miniconda Installation:**
    * Installs Miniconda to `/tmp/miniconda` (for speed, assuming `/tmp` is suitable for your container's lifecycle).
    * Configures Conda channels (conda-forge) and sets `channel_priority` to `strict`.
* **R & Python Conda Environment:**
    * Creates a Conda environment named `r_env` (located at `/tmp/r_env`) with R version 4.3.3 and Python.
    * Includes a mechanism to unset `SPARK_HOME` upon Conda environment activation to prevent conflicts with Conda-installed PySpark.
    * Registers an R kernel (`r433`) for JupyterLab/Notebook.
* **R Package Installation:**
    * Attempts to install R packages listed in `requirements-R.txt` using Conda.
    * Installs a predefined list of additional R packages directly from CRAN if they are not available via Conda or not listed in the file.
* **Verification:** Includes steps to verify the installed versions of Quarto, PySpark, py4j, R, and checks for the presence of key Python and R packages.
* **.bashrc Configuration:** Adds lines to `~/.bashrc` to automatically source Conda and activate the `r_env` environment in new terminal sessions.

## Prerequisites

* An Ubuntu Bionic (18.04 LTS) environment (physical machine, VM, or Docker container).
* `sudo` privileges are required for system package installations and creating directories in `/opt`.
* Internet connection to download packages and installers.
* Bash shell.
* The following files should be present in the same directory as `updatebionic.sh` when you run it:
    * `requirements.txt` (Python packages, primarily for pip)
    * `requirements-python.txt` (Additional Python packages for pip, installed after Conda packages)
    * `requirements-R.txt` (R packages for Conda, e.g., `r-tidyverse`)

## Getting Started

1.  **Clone the Repository (or Download Files):**
    ```bash
    git clone <your-repo-url>
    cd <your-repo-name>
    ```
    Alternatively, download `updatebionic.sh`, `requirements.txt`, `requirements-python.txt`, and `requirements-R.txt` into the same directory.

2.  **Review and Customize (Optional):**
    * **Quarto Version:** Modify `RELEASE_URL` in `updatebionic.sh` if you need a different Quarto version.
    * **R Version:** Change `r-base=4.3.3` in the `conda create` command if a different R version is desired. Remember to update the kernel name and display name if you do.
    * **Package Lists:** Update `requirements.txt`, `requirements-python.txt`, and `requirements-R.txt` with your desired packages.
        * `requirements-R.txt` should list Conda-compatible R package names (e.g., `r-ggplot2`, `r-dplyr`).
    * **CRAN R Packages:** Modify the `R_PACKAGES_CRAN` array in the script for R packages to be installed directly from CRAN.
    * **Conda Python Packages:** Modify the `CONDA_PYTHON_PACKAGES` array for core Python packages to be installed via Conda.

3.  **Make the Script Executable:**
    ```bash
    chmod +x updatebionic.sh
    ```

4.  **Run the Script:**
    ```bash
    ./updatebionic.sh
    ```
    The script will output its progress. Since it involves `sudo` commands, you may be prompted for your password.

## After Running the Script

* **Current Terminal:** To activate the Conda environment in your current terminal session, run:
    ```bash
    source /tmp/miniconda/etc/profile.d/conda.sh
    conda activate /tmp/r_env
    ```
* **New Terminals:** New terminal sessions should automatically activate the `r_env` Conda environment due to the additions to `~/.bashrc`.
* **JupyterLab/Notebook:** When using Jupyter, you should see an option to select the "R 4.3.3" kernel.

## File Structure

* `updatebionic.sh`: The main setup script.
* `requirements.txt`: List of Python packages (primarily for initial pip install).
* `requirements-python.txt`: List of Python packages to be installed with `pip` into the Conda environment (after Conda installs its packages).
* `requirements-R.txt`: List of R packages to be installed with Conda (e.g., `r-tidyverse`).
* `README.md`: This file.

## Build and Test

This project is a shell script, so there isn't a traditional "build" process.

**Testing:**

1.  **Prerequisites:** Ensure you have an Ubuntu Bionic environment (a Docker container is recommended for isolated testing, e.g., `docker run -it --rm ubuntu:bionic`).
2.  **Transfer Files:** Copy the script and requirements files into the test environment.
3.  **Execute:** Run `./updatebionic.sh`.
4.  **Verify:**
    * Check the output for any error messages.
    * After the script completes, manually verify installations:
        * `quarto --version`
        * `python -c "import pyspark; print(pyspark.__version__)"`
        * `python -c "import geopandas; print(geopandas.__version__)"`
        * `R --version`
        * Launch `R` and try loading key packages: `library(tidyverse)`, `library(mapgl)`.
        * Launch `python` and try importing key packages: `import plotnine`, `import pandas`.
    * Open a new terminal to ensure the `.bashrc` modifications work and the Conda environment activates automatically.

## How to Contribute

Contributions are welcome! If you have suggestions for improvements, new features, or bug fixes