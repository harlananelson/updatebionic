# Known Issues and Troubleshooting

## Dependency Warnings (Expected)

When running `setup-lhn-dual-envs.sh`, you will see warnings like:

```
ERROR: pip's dependency resolver does not currently take into account all the packages that are installed.
formulaic 1.1.1 requires pandas>=1.0, but you have pandas 0.25.3 which is incompatible.
lifelines 0.27.8 requires pandas>=1.0.0, but you have pandas 0.25.3 which is incompatible.
plotnine 0.8.0 requires pandas>=1.1.0, but you have pandas 0.25.3 which is incompatible.
```

**This is expected and can be ignored.** We use pandas 0.25.3 for pyspark 2.4.4 compatibility. The packages will still work for most use cases.

## SPARK_HOME Handling

### Issue
The R environment (`/tmp/r_env`) includes an activation script that unsets `SPARK_HOME` to prevent conflicts with conda's pyspark.

### Impact
When you activate `/tmp/r_env`, the system `SPARK_HOME` is unset. This is intentional for the R environment.

### Solution
For Spark work, use the lhn environments (`/tmp/lhn_prod` or `/tmp/lhn_dev`) or the hybrid PySpark kernels which preserve Spark configuration.

## Cloned Conda Environment pip Corruption

### Issue
When cloning conda environments (`conda create --clone`), pip can end up in a corrupted state with mixed version files.

### Symptoms
```
ImportError: cannot import name 'SCHEME_KEYS' from 'pip._internal.models.scheme'
```

### Solution (implemented in v1.0.0)
The setup script now uses `get-pip.py` to install a fresh pip:
```bash
find "$ENV_PATH/lib/python3.7/site-packages" -maxdepth 1 -name "pip*" -exec rm -rf {} +
curl -sS https://bootstrap.pypa.io/pip/3.7/get-pip.py | python
```

## pyarrow Build Failures

### Issue
Installing pyarrow from source on Python 3.10 fails because Arrow C++ libraries aren't available.

### Symptoms
```
Could not find a package configuration file provided by "Arrow"
```

### Solution (implemented in v1.0.0)
Pin pyarrow to a version with pre-built wheels in `requirements-python.txt`:
```
pyarrow==14.0.2
```

## pyspark Version Incompatibility

### Issue
pyspark 2.4.4 doesn't support Python 3.10.

### Solution (implemented in v1.0.0)
- lhn environments (Python 3.7): Use pyspark 2.4.4 from base conda
- R environment (Python 3.10): Use pyspark 3.5.0 in `requirements-python.txt`

## Metastore Connection Issues

### Issue
Upgraded Spark or new environments don't connect to the Hive metastore.

### Symptoms
- `spark.sql("SHOW SCHEMAS")` only returns "default"
- Cannot access any databases

### Root Cause
The metastore configuration is in `/etc/jupyter/configs` and requires `HADOOP_CONF_DIR` to be set.

### Solution
Use the `Spark Upgraded + lhn-*` kernels which set this automatically, or add to your notebook:
```python
import os
os.environ['HADOOP_CONF_DIR'] = '/etc/jupyter/configs'
# Then import pyspark
```

See `SPARK_UPGRADE_TESTING.md` for full details.

## Container Restart

### Issue
All `/tmp/` environments are lost when the container restarts.

### Solution
Re-run `setup-lhn-dual-envs.sh` after each container restart. Your source code in `~/work/Users/hnelson3/` is preserved.

## SSH Key Passphrase Prompts

### Issue
Repeated passphrase prompts during git operations.

### Solution
The setup script starts an ssh-agent. If issues persist:
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

## jupyter-console Compatibility Warnings

### Issue
You may see warnings about jupyter-console requiring newer versions of various packages.

### Impact
These warnings don't affect notebook functionality. The jupyter-console CLI tool may not work correctly, but JupyterLab works fine.

### Solution
Ignore these warnings unless you specifically need the `jupyter console` command.
