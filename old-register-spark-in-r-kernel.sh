
# --- BEGIN ADDED LINES TO HANDLE SPARK_HOME CONFLICT ---
echo "Configuring environment activation for PySpark compatibility..."
ENV_DIR="$R_ENV_PATH"
ACTIVATE_D_DIR="$ENV_DIR/etc/conda/activate.d"
SPARK_UNSET_SCRIPT="$ACTIVATE_D_DIR/unset_spark_home.sh"

# Create the activate.d directory if it doesn't exist
mkdir -p "$ACTIVATE_D_DIR"

# Create the script to unset SPARK_HOME upon activation
echo '#!/bin/bash' > "$SPARK_UNSET_SCRIPT"
echo 'unset SPARK_HOME' >> "$SPARK_UNSET_SCRIPT"

# Make the script executable
chmod +x "$SPARK_UNSET_SCRIPT"
echo "Added SPARK_HOME unset script to $SPARK_UNSET_SCRIPT"
# --- END ADDED LINES TO HANDLE SPARK_HOME CONFLICT ---