# Known Issues and Troubleshooting

## `ModuleNotFoundError: No module named 'plotnine'` on `pyspark-lhn-dev`

### Cause

The hybrid kernels **`pyspark-lhn-dev`** / **`pyspark-lhn-prod`**
(display name **PySpark + lhn-dev (v0.2.0)**) launch **`/opt/conda/bin/python`**
(Docker base) as the driver so Hive metastore + yarn-client work. Plotting
packages from `requirements.txt` live in the per-user clones
(`/tmp/lhn_dev-$USER`) and/or base. If plotnine is only in the clone and the
kernel `PYTHONPATH` does not prepend clone `site-packages`, `import plotnine`
fails even when setup installed it into the clone.

`lhn.plot.plotByTime` needs plotnine at runtime.

### Fix (in setup scripts)

1. `setup-system.sh` / `ensure_plotnine_in_env` install `plotnine==0.8.0` into
   `/opt/conda` (base).
2. `setup-user.sh` always runs `ensure_plotnine_in_env` on lhn_dev (including
   the “already exists — skip rebuild” path) and on base.
3. Hybrid kernel `PYTHONPATH` **prepends** the clone’s `site-packages`.
4. `requirements.txt` pins `plotnine==0.8.0` (last clean py3.7 release).

Re-run `./setup-user.sh`, then **Kernel → Restart** any notebook that was
already open. Morning setup does **not** update a kernel process started
before setup finished.

Quick check on `pyspark-lhn-dev`:

```python
import sys
print(sys.executable)  # expect /opt/conda/bin/python
import plotnine
print(plotnine.__version__)  # expect 0.8.0
from lhn import plotByTime
```

### Order of operations (important)

`lhn.plot` binds `pn` **once** at import time:

```python
try:
    import plotnine as pn
except ImportError:
    pn = None
```

If `lhn` / `lhn.plot` was imported **before** plotnine was available, later
`pip install` or setup does **not** update `lhn.plot.pn`. You must either:

- **Restart the kernel** after plotnine is installed, then import lhn, or  
- **Rebind** after plotnine works:

```python
import plotnine
import lhn.plot
lhn.plot.pn = plotnine   # must be the plotnine package, not lhn.plot
from lhn import plotByTime
```

Do **not** write `import lhn.plot as pn` then `lhn.plot.pn = pn` — that sets
`pn` to the **lhn.plot module** and causes:

```text
AttributeError: module 'lhn.plot' has no attribute 'ggplot'
```

(`ggplot` lives on **plotnine**, not on `lhn.plot`.)

### One-off install (without full setup)

In a notebook on the hybrid kernel (same driver as setup):

```python
import sys
!{sys.executable} -m pip install --user "plotnine==0.8.0"
```

Or in a terminal:

```bash
/opt/conda/bin/python -m pip install --no-cache-dir 'plotnine==0.8.0'
# and/or into the clone:
/tmp/lhn_dev-$(whoami)/bin/python -m pip install --no-cache-dir 'plotnine==0.8.0'
/tmp/lhn_dev-$(whoami)/bin/python -m pip install --no-cache-dir 'pandas==0.25.3' --force-reinstall
```

Then restart the kernel (or rebind `lhn.plot.pn` as above).

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
