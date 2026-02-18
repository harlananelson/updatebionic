# LHN Dual Environment Container Setup

## Overview

This repository provides a **single, comprehensive setup script** for daily use inside the LHN Docker environment:

**`setup-lhn-dual-envs.sh`**

The script provisions:

*   System dependencies and restored SSH access
*   Quarto (system-wide)
*   A modern **R + Python analysis environment**
*   **Two side‑by‑side LHN conda environments** for production vs. development testing
*   Multiple **Jupyter kernels** for Spark, non‑Spark, and hybrid workflows

The design explicitly supports **Spark 2.4.4 + pandas 0.25.x constraints**, while still enabling active development on the refactored LHN codebase.

***

## What This Script Creates

### 1. System Setup

*   Restores SSH keys from persistent storage
*   Installs required system libraries (GDAL, GEOS, PROJ, compilers, fonts)
*   Ensures GitHub SSH connectivity
*   Updates pip in the original Docker conda

***

### 2. Quarto (System-Wide)

*   Installs the **latest Quarto CLI** under:

<!---->

    /opt/quarto/<version>

*   Symlinked to:

<!---->

    /usr/local/bin/quarto

Available immediately in terminals and notebooks.

***

### 3. Miniconda (Fast, Ephemeral)

*   Installed to:

<!---->

    /tmp/miniconda

*   Pinned to a version compatible with **Ubuntu 18.04 (glibc 2.27)**
*   Used for all newly created environments
*   Automatically initialized in `.bashrc`

***

## Environments Created

### A. R + Python Analysis Environment

**Path:**

    /tmp/r_env

**Versions**

*   R: **4.4.0**
*   Python: **3.10**

**Purpose**

*   R analysis
*   Python ML (non‑Spark)
*   Quarto documents
*   Plotting, modeling, reporting

**Installed**

*   Python packages from `requirements-python.txt`
*   R packages from:
    *   `requirements-R.txt` (conda)
    *   CRAN (fallback + additional modeling packages)
    *   GitHub (`treeshap`)
*   `reticulate` fully configured

**Jupyter Kernels**

*   `Python 3.10 (r_env)`
*   `R 4.4.0 (r_env)`

This environment is **auto‑activated in new terminals**.

***

### B. LHN Production Environment (`lhn_prod`)

**Path:**

    /tmp/lhn_prod

**LHN Version**

*   `v0.1.0-monolithic`

**Source Location**

    /tmp/lhn_prod_src

(ephemeral, fast)

**Key Characteristics**

*   Cloned from original Docker `base` conda
*   Python **3.7**
*   pandas **0.25.3** (required for Spark 2.4.4)
*   Editable install (`pip install -e`)
*   Aggressively repairs broken `pip` and `pandas` caused by conda cloning

**Jupyter Kernel**

*   `Python (lhn-prod v0.1.0)`

Used for **production validation and regression testing**.

***

### C. LHN Development Environment (`lhn_dev`)

**Path:**

    /tmp/lhn_dev

**LHN Version**

*   `v0.2.0-dev` (refactored)

**Source Location (persistent)**

    ~/work/Users/hnelson3/lhn

**Additional Dependencies**

*   `spark_config_mapper` (persistent)
*   `omop_concept_mapper` (optional)

**Key Characteristics**

*   Python **3.7**
*   pandas **0.25.3**
*   Uses `--no-deps` installs to bypass incompatible `pandas>=1.0` requirements
*   Editable install for active development

**Jupyter Kernel**

*   `Python (lhn-dev v0.2.0)`

Used for **refactoring, feature work, and side‑by‑side comparison**.

***

## Spark & Jupyter Kernel Strategy

### Recommended (Hive Metastore Access ✅)

These kernels use the **original Docker PySpark** and automatically inject LHN paths:

*   **PySpark + lhn-prod (v0.1.0)**
*   **PySpark + lhn-dev (v0.2.0)**

✅ Full database access  
✅ No `sys.path` hacks needed  
✅ Safest for Spark work

***

### Upgraded Spark Kernels (Optional)

If you upgrade `pyspark` inside `lhn_prod` or `lhn_dev`, the script also creates:

*   **Spark Upgraded + lhn-prod (Metastore)**
*   **Spark Upgraded + lhn-dev (Metastore)**

These preserve Hive access via `HADOOP_CONF_DIR`.

***

### Non-Spark Kernels

*   `Python (lhn-prod v0.1.0)`
*   `Python (lhn-dev v0.2.0)`
*   `Python 3.10 (r_env)`
*   `R 4.4.0 (r_env)`

Useful for unit tests, modeling, and analysis **without Spark**.

***

## Pandas Compatibility (Important)

Both LHN environments **intentionally pin**:

    pandas==0.25.3

Reason:

*   Required for **Spark 2.4.4**
*   Newer pandas versions break Spark internals

The refactored LHN code declares `pandas>=1.0` but is installed with:

    pip install --no-deps

If you encounter pandas-related errors, the code may need to be adapted to the 0.25.x API.

***

## Usage

### Run the Setup

```bash
chmod +x setup-lhn-dual-envs.sh
./setup-lhn-dual-envs.sh
```

The script is **idempotent** and safe to re-run.

***

### Switching Conda Contexts

Added to `.bashrc`:

```bash
oldbase   # Activate original Docker conda (Spark lives here)
oldconda  # Make /opt/conda available without activating
```

***

### Activate Environments Manually

```bash
conda activate /tmp/r_env
conda activate /tmp/lhn_prod
conda activate /tmp/lhn_dev
```

***

## File Expectations

The script expects these files **next to itself**:

    requirements.txt
    requirements-python.txt
    requirements-R.txt

Persistent repositories must exist at:

    ~/work/Users/hnelson3/lhn
    ~/work/Users/hnelson3/spark_config_mapper
    ~/work/Users/hnelson3/omop_concept_mapper (optional)

***

## Design Philosophy

*   **Side-by-side reproducibility**
*   **Fast ephemeral envs**, persistent source
*   **Spark compatibility first**
*   **Editable installs everywhere**
*   No Docker changes required

***

## Summary

After running this script you have:

*   ✅ R 4.4 + Python 3.10 analysis environment
*   ✅ LHN production and development environments
*   ✅ Spark-safe kernels with Hive access
*   ✅ Quarto ready for publishing
*   ✅ One command rebuild when the container resets

This setup is optimized for **daily, real-world LHN development and validation**.
