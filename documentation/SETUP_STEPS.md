# Container Setup Steps

This document provides step-by-step instructions for setting up the IU Health Datalab container environment with dual lhn environments for development and production testing.

## Quick Start

```bash
# 1. Clone or update the setup repository
cd ~/work/Users/hnelson3
git clone https://github.com/harlananelson/updatebionic.git
# OR if already cloned:
cd ~/work/Users/hnelson3/updatebionic && git pull

# 2. Run the setup script
chmod +x setup-lhn-dual-envs.sh
./setup-lhn-dual-envs.sh
```

## Prerequisites

Before running the setup script, ensure you have:

1. **SSH keys in persistent storage** at `~/work/Users/hnelson3/.ssh/`
   - `id_ed25519` (private key)
   - `id_ed25519.pub` (public key)
   - Public key added to GitHub

2. **Source repositories cloned to persistent storage:**
   - `~/work/Users/hnelson3/lhn` - Main lhn repository (main branch)
   - `~/work/Users/hnelson3/spark_config_mapper` - Spark configuration utility
   - `~/work/Users/hnelson3/omop_concept_mapper` - OMOP concept mapping utility

### First-Time SSH Setup

If you don't have SSH keys set up:

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy to persistent storage
mkdir -p ~/work/Users/hnelson3/.ssh
cp ~/.ssh/id_ed25519 ~/work/Users/hnelson3/.ssh/
cp ~/.ssh/id_ed25519.pub ~/work/Users/hnelson3/.ssh/

# Add public key to GitHub
cat ~/.ssh/id_ed25519.pub
# Copy output to GitHub.com -> Settings -> SSH keys
```

### First-Time Repository Setup

```bash
cd ~/work/Users/hnelson3

# Clone lhn (development version)
git clone git@github.com:harlananelson/lhn.git

# Clone spark_config_mapper
git clone git@github.com:harlananelson/spark_config_mapper.git

# Clone omop_concept_mapper
git clone git@github.com:harlananelson/omop_concept_mapper.git
```

## What the Script Creates

### Environments

| Environment | Location | Python | Purpose |
|-------------|----------|--------|---------|
| lhn_prod | `/tmp/lhn_prod` | 3.7 | Production testing (v0.1.0 monolithic) |
| lhn_dev | `/tmp/lhn_dev` | 3.7 | Development testing (v0.2.0 refactored) |
| r_env | `/tmp/r_env` | 3.10 | R 4.4.0 + Python ML work |

### Jupyter Kernels

| Kernel | Description | Use Case |
|--------|-------------|----------|
| **PySpark + lhn-prod (v0.1.0)** | Base pyspark + production lhn | Production Spark work with metastore |
| **PySpark + lhn-dev (v0.2.0)** | Base pyspark + development lhn | Development Spark work with metastore |
| **Spark Upgraded + lhn-prod** | lhn_prod env with metastore config | Testing upgraded Spark versions |
| **Spark Upgraded + lhn-dev** | lhn_dev env with metastore config | Testing upgraded Spark versions |
| **Python (lhn-prod v0.1.0)** | lhn_prod standalone | Non-Spark testing |
| **Python (lhn-dev v0.2.0)** | lhn_dev standalone | Non-Spark testing |
| **Python 3.10 (r_env)** | Python ML environment | Machine learning work |
| **R 4.4.0 (r_env)** | R analysis environment | R statistical work |

### Installed Tools

- **Quarto**: Latest version installed to `/opt/quarto/`
- **Miniconda**: Installed to `/tmp/miniconda/` for environment management

## Post-Setup Usage

### Recommended Workflow

For **PySpark work with Hive metastore access**, use the hybrid kernels:
- `PySpark + lhn-dev (v0.2.0)` - Recommended for most work
- `PySpark + lhn-prod (v0.1.0)` - For production comparison testing

These kernels automatically include lhn in the Python path - no `sys.path` modification needed.

### Terminal Commands

```bash
# Activate R environment (default after setup)
conda activate /tmp/r_env

# Switch to production lhn environment
conda activate /tmp/lhn_prod

# Switch to development lhn environment
conda activate /tmp/lhn_dev

# Access original Docker conda (has pyspark 2.4.4)
oldbase

# Make original /opt/conda available without activating
oldconda
```

### Verifying Installation

```bash
# Check lhn import
conda activate /tmp/lhn_dev
python -c "import lhn; print('lhn OK')"

# Check Spark
python -c "import pyspark; print(f'pyspark {pyspark.__version__}')"

# Check R
R --version

# Check Quarto
quarto --version
```

## Upgrading Spark

The `Spark Upgraded` kernels are configured to connect to the Hive metastore. To test an upgraded Spark version:

```bash
# Activate the environment
conda activate /tmp/lhn_dev

# Install upgraded pyspark
pip install pyspark==3.3.0  # or desired version

# Use the "Spark Upgraded + lhn-dev (Metastore)" kernel
```

See `documentation/SPARK_UPGRADE_TESTING.md` for detailed instructions.

## Important Notes

### Pandas Version

Both lhn environments use **pandas 0.25.3** for compatibility with pyspark 2.4.4. You will see dependency warnings from packages that want pandas >= 1.0 - these are expected and can be ignored.

### Metastore Access

The standard lhn kernels (`Python (lhn-prod)` and `Python (lhn-dev)`) do **not** have Hive metastore access. For database access, use:
- The `PySpark + lhn-*` kernels (recommended)
- The `Spark Upgraded + lhn-*` kernels (for upgraded Spark testing)

### Ephemeral vs Persistent Storage

| Location | Type | Purpose |
|----------|------|---------|
| `/tmp/` | Ephemeral | Environments (fast, lost on restart) |
| `~/work/Users/hnelson3/` | Persistent | Source code, SSH keys, data |

After a container restart, re-run `setup-lhn-dual-envs.sh` to recreate the environments.

## Troubleshooting

### "Only default schema found" in Spark

The SparkSession isn't connected to the metastore. Use one of the `PySpark + lhn-*` or `Spark Upgraded + lhn-*` kernels instead.

### pip errors during setup

The script uses `get-pip.py` to fix corrupted pip installations from conda cloning. If pip errors persist, try:

```bash
curl -sS https://bootstrap.pypa.io/pip/3.7/get-pip.py | python
```

### SSH key passphrase prompts

The script starts an ssh-agent and adds your key. If you're still prompted, ensure your key is in `~/.ssh/` and run:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

## File Reference

| File | Purpose |
|------|---------|
| `setup-lhn-dual-envs.sh` | Main setup script |
| `requirements.txt` | Python packages for lhn environments |
| `requirements-python.txt` | Python packages for R environment (Python 3.10) |
| `requirements-R.txt` | R packages via conda |
| `diagnose_spark_config.py` | Capture working Spark configuration |
| `spark_metastore_init.py` | Notebook cell for upgraded Spark init |

## Version History

- **v1.0.0** (2026-01-29): First stable release
  - Fixed pip corruption in cloned conda environments
  - Added Spark upgrade kernels with metastore support
  - Added diagnostic tools for Spark configuration
  - Pinned pyarrow/pyspark for Python 3.10 compatibility
