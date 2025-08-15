# Ubuntu Bionic Data Science Environment Setup

## Overview

This repository provides automated setup scripts for creating comprehensive data science environments in Ubuntu Bionic Docker containers. Choose between two setup options based on your needs:

- **`updatebionic.sh`** - R-focused data science environment with Python integration
- **`updatebionic-ml.sh`** - Complete setup including the R environment PLUS a dedicated machine learning environment

## Script Options

### Option 1: Standard Data Science Environment (`updatebionic.sh`)

Creates a single R-focused environment with Python integration:
- **R Environment**: R 4.3.3 with Python 3.10 integration
- **Python Packages**: Data science tools (pandas, plotnine, geopandas, etc.)
- **R Packages**: Tidyverse, data.table, tidymodels, and more
- **Tools**: Quarto CLI, Jupyter kernels for both R and Python

### Option 2: Extended ML Environment (`updatebionic-ml.sh`)

Includes everything from Option 1 PLUS a dedicated ML environment:
- **R Environment**: Same as Option 1 (R 4.3.3 + Python 3.10)
- **ML Environment**: Separate Python 3.12.2 environment optimized for machine learning
  - PyTorch with CUDA 12.4 support
  - scikit-learn, TensorBoard, Weights & Biases
  - Uses `environment-ml.yml` configuration from Zhiu Tu (Purdue University)
- **Isolation**: ML environment is separate to avoid conflicts with PySpark in the R environment

## Features

Both scripts provide:

* **System Updates:** Updates `apt` package lists and installs geospatial dependencies
* **Base Conda Environment Updates:** Updates Python packages in the base Conda environment from `requirements.txt` using `pip` (excludes `pyspark` to preserve existing version)
* **Quarto Installation:** Downloads and installs Quarto CLI (v1.3.450) to `/opt/quarto`
* **Miniconda Installation:** Sets up Miniconda in `/tmp` for fast, temporary environments
* **R Environment:** Creates R 4.3.3 environment with Python 3.10 integration
* **Jupyter Integration:** Registers kernels for both R and Python environments
* **Automatic Activation:** Configures `.bashrc` for automatic environment activation

Additional features in `updatebionic-ml.sh`:
* **ML Environment:** Dedicated Python 3.12.2 environment with PyTorch and CUDA support
* **Advanced ML Tools:** TensorBoard, Weights & Biases, advanced PyTorch ecosystem
* **Multiple Kernels:** Separate Jupyter kernels for R, standard Python, and ML Python environments

## Required Files

Ensure these files are in the same directory as your chosen script:

### For Both Scripts:
- `requirements.txt` - Python packages for base Conda environment (excludes `pyspark`)
- `requirements-python.txt` - Python packages for the R environment
- `requirements-R.txt` - R packages to install via Conda and CRAN

### Additional for ML Script:
- `environment-ml.yml` - ML environment specification (from Zhiu Tu, Purdue University)

## User Instructions

### Choose Your Setup

**For standard data science work (R + Python):**
```bash
chmod +x updatebionic.sh
./updatebionic.sh
```

**For data science + dedicated ML environment:**
```bash
chmod +x updatebionic-ml.sh
./updatebionic-ml.sh
```

### Steps to Run

1. **Prepare Files:**
   - Place your chosen script and required files in the same directory
   - Review `requirements.txt` - this updates the base Conda environment via `pip` (excludes `pyspark`)
   - Check `requirements-python.txt` and `requirements-R.txt` for environment-specific packages
   - If using ML script, ensure `environment-ml.yml` is present

2. **Make the Script Executable:**
   ```bash
   chmod +x updatebionic.sh        # For standard setup
   # OR
   chmod +x updatebionic-ml.sh     # For ML-extended setup
   ```

3. **Run the Script:**
   ```bash
   ./updatebionic.sh               # For standard setup
   # OR
   ./updatebionic-ml.sh            # For ML-extended setup
   ```
   - Scripts require `sudo` privileges for system installations
   - You may be prompted for a password during execution

4. **Activate the Environment (Current Terminal):**
   
   **For standard setup:**
   ```bash
   source /tmp/miniconda/etc/profile.d/conda.sh
   conda activate /tmp/r_env
   ```
   
   **For ML setup:**
   ```bash
   source /tmp/miniconda/etc/profile.d/conda.sh
   conda activate /tmp/r_env        # For R and standard Python work
   # OR
   conda activate /tmp/ml_env       # For machine learning work
   ```

5. **Use the Environment:**
   - New terminal sessions automatically activate the R environment via `.bashrc`
   - **Jupyter Kernels Available:**
     - **R 4.3.3** - For R notebooks and analysis
     - **Python 3.10 (r_env)** - For Python work integrated with R environment
     - **Python 3.12 (ml_env)** - For machine learning (ML setup only)
   - Use Quarto with the `quarto` command for publishing

6. **Troubleshooting:**
   - Check the script's output for errors and note any line numbers
   - Verify installations:
     ```bash
     quarto --version
     python -c "import plotnine; print(plotnine.__version__)"
     R -e "library(tidyverse)"
     ```
   - For ML environment (if using ML script):
     ```bash
     conda activate /tmp/ml_env
     python -c "import torch; print(torch.__version__)"
     ```
   - If errors occur, share the specific error message and line number

## Environment Details

### Base Conda Environment
- **Purpose:** System-wide Python packages, updated but stable
- **Python Packages:** From `requirements.txt` via `pip`
- **Note:** `pyspark` is intentionally excluded to preserve existing version

### R Environment (`/tmp/r_env`)
- **R Version:** 4.3.3
- **Python Version:** 3.10 (integrated with R)
- **Purpose:** Primary environment for data science workflows
- **Packages:** Data analysis, visualization, geospatial tools
- **PySpark Compatibility:** Configured to work with existing PySpark installation

### ML Environment (`/tmp/ml_env`) - ML Setup Only
- **Python Version:** 3.12.2
- **Purpose:** Dedicated machine learning environment
- **Key Features:**
  - PyTorch with CUDA 12.4 support
  - TensorBoard, Weights & Biases integration
  - Latest ML libraries and tools
  - Isolated from PySpark to prevent conflicts
- **Configuration:** Based on `environment-ml.yml` from Zhiu Tu (Purdue University)

## Prerequisites

- Ubuntu Bionic Docker container
- User with `sudo` privileges
- Internet connection for package downloads
- Sufficient disk space (environments are created in `/tmp` for speed)

## LLM Instructions

This section guides AI assistants in helping users with these setup scripts:

### General Principles
- **Minimal Changes:** Provide targeted fixes that modify only relevant lines
- **Error Focus:** Request exact error messages and line numbers when available
- **Preserve Functionality:** Don't rewrite entire scripts unless absolutely necessary

### User Constraints
- **Environment:** Ubuntu Bionic Docker container with user-level permissions
- **No System Modifications:** Cannot modify Docker setup or system outside container
- **Package Management:** 
  - Base environment: Update via `requirements.txt` using `pip` (exclude `pyspark`)
  - R environment: Install from `requirements-python.txt` and `requirements-R.txt`
  - ML environment: Use `environment-ml.yml` specification

### Common Issues and Solutions
- **R Package Installation (Line ~192):** If errors occur in the R package loop, add `set -x` before the loop and `set +x` after for debugging
- **Conda Package Availability:** Check if packages exist on `conda-forge`; fall back to CRAN/PyPI as needed
- **Environment Conflicts:** ML environment is separate to avoid PySpark conflicts
- **Permission Issues:** Scripts handle `/tmp` directory permissions and `.bashrc` ownership

### Script Selection Guidance
- **Standard Setup:** Use `updatebionic.sh` for general data science work
- **ML-Extended Setup:** Use `updatebionic-ml.sh` when PyTorch/CUDA/advanced ML tools are needed
- **File Requirements:** Ensure all required files are present before running

### Response Guidelines
- Provide clear, concise fixes with code snippets
- Explain why changes address the specific issue
- Reference appropriate files (`requirements.txt`, `environment-ml.yml`, etc.)
- Avoid generating unrelated modifications

Example: If `r-tidyverse` installation fails, verify availability on `conda-forge`. If unavailable, suggest adding `tidyverse` to the `R_PACKAGES_CRAN` array in the script for CRAN installation.

## File Structure

```
updatebionic/
├── updatebionic.sh              # Standard data science setup
├── updatebionic-ml.sh           # ML-extended setup
├── requirements.txt             # Base Conda environment packages
├── requirements-python.txt      # R environment Python packages  
├── requirements-R.txt           # R packages for Conda/CRAN installation
├── environment-ml.yml           # ML environment specification
└── README.md                    # This file
```

## Credits

- **ML Environment Configuration:** `environment-ml.yml` provided by Zhiu Tu, Purdue University
- **Base Setup:** Adapted for Ubuntu Bionic Docker containers with R and Python integration