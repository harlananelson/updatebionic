Looking at your `updatebionic.sh` script, I don't see any explicit removal of Spark variables, but there are a few places where environment issues could occur:

## Potential Issues in Your Script

### 1. SPARK_HOME Conflict Handling
**Lines 113-124:** Your script actually **intentionally unsets SPARK_HOME**:

```bash
# --- BEGIN ADDED LINES TO HANDLE SPARK_HOME CONFLICT ---
echo "Configuring environment activation for PySpark compatibility..."
ENV_DIR="$R_ENV_PATH"
ACTIVATE_D_DIR="$ENV_DIR/etc/conda/activate.d"
SPARK_UNSET_SCRIPT="$ACTIVATE_D_DIR/unset_spark_home.sh"

# Create the script to unset SPARK_HOME upon activation
echo '#!/bin/bash' > "$SPARK_UNSET_SCRIPT"
echo 'unset SPARK_HOME' >> "$SPARK_UNSET_SCRIPT"
```

**This is likely the culprit!** When you activate the conda environment (`/tmp/r_env`), it runs this script that unsets `SPARK_HOME`.

### 2. .bashrc Modifications
**Lines 245-258:** The script modifies `.bashrc` and changes ownership:

```bash
if [ -f "$HOME/.bashrc" ]; then
  grep -q "source /tmp/miniconda/etc/profile.d/conda.sh" "$HOME/.bashrc" || echo "source /tmp/miniconda/etc/profile.d/conda.sh" >> "$HOME/.bashrc"
  grep -q "conda activate $R_ENV_PATH" "$HOME/.bashrc" || echo "conda activate $R_ENV_PATH" >> "$HOME/.bashrc"
  sudo chown "$USER":"$(id -gn)" "$HOME/.bashrc"
```

## Solutions

### Option 1: Modify the Unset Script
Edit the conda activation script to preserve system Spark:

```bash
# Check what's in the unset script
cat /tmp/r_env/etc/conda/activate.d/unset_spark_home.sh

# Modify it to only unset if it conflicts
echo '#!/bin/bash
# Only unset SPARK_HOME if it points to conda spark
if [[ "$SPARK_HOME" == *"conda"* ]] || [[ "$SPARK_HOME" == *"miniconda"* ]]; then
    unset SPARK_HOME
fi' > /tmp/r_env/etc/conda/activate.d/unset_spark_home.sh
```

### Option 2: Set SPARK_HOME After Conda Activation
Add to your `.bashrc` after the conda activation lines:

```bash
# Add this to ~/.bashrc after the conda activation
export SPARK_HOME=/usr/local/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
```

### Option 3: Use Different Spark for Different Tasks
Keep the conda environment for R/Python data science, but use system Spark separately:

```bash
# Deactivate conda when you need system Spark
conda deactivate
export SPARK_HOME=/usr/local/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
spark-submit --version
```

## Quick Fix
Since you're currently in the `/tmp/r_env` environment, try:

```bash
# Temporarily restore Spark in current session
export SPARK_HOME=/usr/local/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
spark-submit --version
```

The script was designed to prevent Spark conflicts with PySpark, but it's being overly aggressive by unsetting your system Spark installation.