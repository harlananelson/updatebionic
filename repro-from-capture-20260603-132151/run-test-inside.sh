#!/bin/bash
set -euo pipefail

echo "=== Inside reproduction container as $(whoami) (UID $(id -u)) ==="
echo "PATH: $PATH"
echo "Python: $(python --version 2>/dev/null || echo no python in PATH)"
echo "/opt/conda python: $(/opt/conda/bin/python --version 2>/dev/null || echo missing)"

# Copy the current scripts from the mounted volume.
if [ -d /host-updatebionic ]; then
    echo "Host updatebionic dir is mounted at /host-updatebionic"
    cp /host-updatebionic/setup-system.sh /host-updatebionic/setup-user.sh /host-updatebionic/add-r-kernel.sh . 2>/dev/null || true
    chmod +x setup-system.sh setup-user.sh add-r-kernel.sh 2>/dev/null || true
else
    echo "WARNING: /host-updatebionic not mounted — scripts must be provided another way."
fi

# Capture dir for inspection (metadata)
if [ -d /capture ]; then
    echo "Capture metadata available at /capture"
    ls /capture/ | head -15
fi

# Packs (for seeding golden envs)
if [ -d /capture-packs ]; then
    echo "Captured conda packs available at /capture-packs:"
    ls -l /capture-packs/*.tar.gz 2>/dev/null | head -10 || true
fi

echo ""
echo "========== Phase 1: Run current setup scripts on clean base (test script correctness) =========="
echo "=== Running setup-system.sh ==="
./setup-system.sh || echo "setup-system.sh exited with code $?"

echo ""
echo "=== Running setup-user.sh ==="
./setup-user.sh || echo "setup-user.sh exited with code $?"

echo ""
echo "=== Post-setup (from scripts) inspection ==="
echo "Conda envs (may use wrong conda in PATH; we will use explicit paths too):"
/opt/conda/bin/conda env list 2>/dev/null || /tmp/miniconda/bin/conda env list 2>/dev/null || conda env list || true

echo ""
echo "ls -ld /tmp/*env* /tmp/miniconda /opt/conda 2>/dev/null | cat"
ls -ld /tmp/*env* /tmp/miniconda /opt/conda 2>/dev/null | cat || true

echo ""
echo "Jupyter kernels (registered for this user):"
jupyter kernelspec list 2>/dev/null || echo "jupyter not in PATH or no kernels registered yet"

# The user that setup ran as (inside container usually "testuser")
TESTUSER="${USER:-testuser}"
R_ENV_PRODUCED="/tmp/r_env-${TESTUSER}"
LHN_PROD_PRODUCED="/tmp/lhn_prod-${TESTUSER}"
LHN_DEV_PRODUCED="/tmp/lhn_dev-${TESTUSER}"

echo ""
echo "=== Smoke tests on envs produced by the *current* scripts ==="

if [ -d "$R_ENV_PRODUCED" ]; then
    echo "Found produced R env: $R_ENV_PRODUCED"
    "$R_ENV_PRODUCED/bin/python" --version || true
    "$R_ENV_PRODUCED/bin/R" --version | head -1 || true
    echo "Testing reticulate + plotnine from R in produced r_env..."
    "$R_ENV_PRODUCED/bin/R" -e '
library(reticulate)
print("reticulate loaded")
py_config()
print("Trying to import plotnine via reticulate...")
try({ p9 <- import("plotnine"); print(paste("plotnine version:", p9$__version__)) }, silent = TRUE)
' 2>&1 | tail -15 || true
else
    echo "No r_env produced for ${TESTUSER} (may be expected if setup-user had issues or was skipped)."
fi

# Quick check one of the lhn clones (they are the "old side with adds")
for lhn in "$LHN_DEV_PRODUCED" "$LHN_PROD_PRODUCED"; do
    if [ -d "$lhn" ]; then
        echo "Found lhn env: $lhn"
        "$lhn/bin/python" --version || true
        "$lhn/bin/python" -c "
import sys
print('prefix:', sys.prefix)
try:
    import pandas
    print('pandas:', pandas.__version__)
except Exception as e: print('pandas import:', e)
try:
    import pyspark
    print('pyspark:', pyspark.__version__)
except Exception as e: print('pyspark import note (may be expected):', type(e).__name__)
" 2>&1 | cat || true
    fi
done

echo ""
echo "========== Phase 2: Seed + smoke any captured full env packs (golden state validation) =========="
if [ -x ./seed-from-captured-packs.sh ] && [ -d /capture-packs ]; then
    ./seed-from-captured-packs.sh || true
else
    echo "(no seed script or no /capture-packs; skipping golden env seeding)"
fi

echo ""
echo "=== Smoke tests against any seeded golden envs (from capture) ==="
# Discover any r_env* or lhn* or miniconda that are now under /tmp (seeded or produced)
for candidate in /tmp/r_env-* /tmp/lhn_prod-* /tmp/lhn_dev-* /tmp/miniconda; do
    if [ -d "$candidate" ] && [ -x "$candidate/bin/python" ]; then
        echo ""
        echo "Golden/seeded candidate: $candidate"
        "$candidate/bin/python" --version 2>/dev/null | cat || true
        if [ -x "$candidate/bin/R" ]; then
            "$candidate/bin/R" --version 2>/dev/null | head -1 | cat || true
            echo "  reticulate test (if reticulate present)..."
            "$candidate/bin/R" -e '
if (requireNamespace("reticulate", quietly=TRUE)) {
  library(reticulate)
  print("reticulate loaded")
  py_config()
  try({ p9 <- import("plotnine"); print(paste("plotnine:", p9$__version__)) }, silent=TRUE)
} else print("no reticulate in this env")
' 2>&1 | tail -10 || true
        fi
    fi
done

echo ""
echo "=== Test run inside container finished ==="
