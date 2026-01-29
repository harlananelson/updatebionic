# Quick Reference Card

## Daily Container Setup

```bash
cd ~/work/Users/hnelson3/updatebionic
git pull
./setup-lhn-dual-envs.sh
```

## Kernel Selection Guide

| Task | Recommended Kernel |
|------|-------------------|
| PySpark with lhn (development) | PySpark + lhn-dev (v0.2.0) |
| PySpark with lhn (production) | PySpark + lhn-prod (v0.1.0) |
| Testing upgraded Spark | Spark Upgraded + lhn-dev (Metastore) |
| Python ML work (no Spark) | Python 3.10 (r_env) |
| R analysis | R 4.4.0 (r_env) |

## Terminal Commands

```bash
# Environment activation
conda activate /tmp/lhn_dev      # Development lhn
conda activate /tmp/lhn_prod     # Production lhn
conda activate /tmp/r_env        # R + Python 3.10

# Switch to original Docker conda
oldbase                          # Activate base from /opt/conda
oldconda                         # Make /opt/conda available

# Verify installations
python -c "import lhn"           # Test lhn import
python -c "import pyspark"       # Test pyspark
quarto --version                 # Check Quarto
R --version                      # Check R
```

## Key Paths

| Item | Path |
|------|------|
| Development lhn source | `~/work/Users/hnelson3/lhn` |
| Production lhn source | `/tmp/lhn_prod_src` |
| spark_config_mapper | `~/work/Users/hnelson3/spark_config_mapper` |
| Metastore config | `/etc/jupyter/configs` |
| Quarto | `/opt/quarto/` |

## Spark Metastore Quick Fix

If Spark only shows "default" schema, add this at the top of your notebook:

```python
import os
os.environ['HADOOP_CONF_DIR'] = '/etc/jupyter/configs'
# Then import pyspark
```

## Upgrading Spark

```bash
conda activate /tmp/lhn_dev
pip install pyspark==3.3.0
# Use "Spark Upgraded + lhn-dev (Metastore)" kernel
```

## Documentation Files

- `SETUP_STEPS.md` - Full setup instructions
- `SPARK_UPGRADE_TESTING.md` - Spark upgrade guide
- `KNOWN_ISSUES.md` - Troubleshooting
- `spark-info.md` - Base Spark installation info
