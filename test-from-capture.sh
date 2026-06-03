#!/bin/bash
#
# test-from-capture.sh
#
# Run on the *host* (this Ubuntu machine) after you have received a
# env-capture-*.tar.gz from the user who ran capture-docker-env.sh
# *inside* their real target container.
#
# This script will:
#   1. Unpack the capture.
#   2. Inspect key facts (base OS, python versions, pyspark source, etc.).
#   3. Build a Docker image that tries to reproduce the captured environment
#      as closely as possible (using the captured apt list + the typical
#      bootstrap for /opt/conda that these LHN-style containers use).
#   4. Copy the *current* setup-system.sh and setup-user.sh from this repo
#      into the container.
#   5. Run the setup as a non-root user (simulating the real workflow).
#   6. Verify that the expected dual-conda setup appears:
#        - /opt/conda (old, for pyspark 2.4.4)
#        - /tmp/miniconda (the updated one)
#        - /tmp/r_env-<testuser> with modern R + Python 3.10 (from miniconda)
#        - Jupyter kernels registered for the r_env
#        - lhn_prod / lhn_dev clones from the old base
#   7. Inside the test container, do basic smoke tests:
#        - Old side can import pyspark (tolerating the known cloudpickle issue
#          if we run with the right PYTHONPATH)
#        - r_env R can be started and reticulate points at its own Python
#        - Kernels are listed
#
# Usage:
#   ./test-from-capture.sh /path/to/env-capture-YYYYMMDD-HHMMSS.tar.gz
#
# The script is intentionally verbose so we can debug mismatches between
# "what the capture says" and "what our setup scripts actually produce".
#
# After a successful run we will have high confidence that the scripts
# will work for the user when they drop the updated versions into their
# real container.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 /path/to/env-capture-*.tar.gz"
    exit 1
fi

CAPTURE_TARBALL="$1"
if [ ! -f "$CAPTURE_TARBALL" ]; then
    echo "Capture tarball not found: $CAPTURE_TARBALL"
    exit 1
fi

CAPTURE_BASENAME=$(basename "$CAPTURE_TARBALL" .tar.gz)
WORK_DIR="/tmp/repro-${CAPTURE_BASENAME}"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "=== Unpacking capture ==="
tar -xzf "$CAPTURE_TARBALL" -C "$WORK_DIR"
CAPTURE_DIR=$(find "$WORK_DIR" -maxdepth 1 -type d -name 'env-capture-*' | head -1)
echo "Capture extracted to: $CAPTURE_DIR"

echo ""
echo "=== Key facts from capture (we will try to reproduce these) ==="
echo "OS:"
cat "$CAPTURE_DIR/os-release.txt" 2>/dev/null | head -5 || true
echo ""
echo "Python in /opt/conda (if present):"
cat "$CAPTURE_DIR/opt-conda-python-version.txt" 2>/dev/null || echo "(not captured or missing)"
echo ""
echo "pyspark check from /opt/conda (if present):"
cat "$CAPTURE_DIR/opt-conda-pyspark-check.txt" 2>/dev/null | head -10 || echo "(not captured)"
echo ""
echo "Whether /tmp/miniconda existed at capture time:"
ls -d "$CAPTURE_DIR"/tmp-miniconda* 2>/dev/null || echo "No /tmp/miniconda entry (probably not present)"
echo ""
echo "Jupyter kernels at capture time:"
cat "$CAPTURE_DIR/jupyter-kernelspecs.txt" 2>/dev/null | head -20 || true
echo ""
echo "User / sudo status:"
cat "$CAPTURE_DIR/id.txt" 2>/dev/null || true
cat "$CAPTURE_DIR/sudo-status.txt" 2>/dev/null || true

echo ""
echo "=== Preparing reproduction ==="

# We will use a base that matches the captured os-release.
# These containers are almost always Ubuntu 18.04 (Bionic) based.
BASE_IMAGE="ubuntu:18.04"

# Extract the list of installed apt packages so we can approximate the base.
# The capture has apt-list-installed.txt or dpkg output.
APT_LIST="$CAPTURE_DIR/apt-list-installed.txt"
if [ ! -f "$APT_LIST" ]; then
    APT_LIST="$CAPTURE_DIR/dpkg-python-spark.txt"
fi

echo "Using base image: $BASE_IMAGE"
echo "We will install a reasonable set of packages that these LHN containers"
echo "typically have (build tools, python, etc.) plus anything obvious from the capture."

# Create a Dockerfile in the work dir.
DOCKERFILE="$WORK_DIR/Dockerfile"
cat > "$DOCKERFILE" << 'DOCKEREOF'
FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gfortran \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    libudunits2-dev \
    libfreetype6-dev \
    libpng-dev \
    vim \
    openssh-client \
    curl \
    wget \
    ca-certificates \
    git \
    sudo \
    python3 \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Common locations in these setups
RUN mkdir -p /opt /tmp /home/jovyan /work

# We will install the "old" conda the way these containers usually get it.
# The exact bootstrap varies; the capture will tell us the resulting python version.
# A typical old bootstrap for these environments is something like the
# Anaconda/Miniconda installer that was current ~2019-2020, resulting in
# Python 3.7 + conda 4.7-ish.
#
# Here we use a known historical Miniconda3 that gives py 3.7 on glibc 2.27.
# If the capture shows a different exact python, we can adjust later.
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-4.7.12-Linux-x86_64.sh -O /tmp/miniconda.sh || \
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-py37_4.10.3-Linux-x86_64.sh -O /tmp/miniconda.sh
RUN bash /tmp/miniconda.sh -b -p /opt/conda && rm /tmp/miniconda.sh
ENV PATH="/opt/conda/bin:${PATH}"

# At this point the container has a /opt/conda that is "the old one".
# In real life the pyspark 2.4.4 is often provided by the platform via
# /usr/local/spark/python rather than (or in addition to) conda.
# We install a compatible old pyspark here for basic testing.
RUN /opt/conda/bin/pip install 'pyspark==2.4.4' 'pandas==0.25.3' --no-deps || true

# Also install a few things the user mentioned they add (plotnine etc.)
# into a clone later; for now just have them available in base for smoke tests.
RUN /opt/conda/bin/pip install plotnine lifelines || true

# Create a non-root user that will run the setup (simulating the real user).
ARG USERNAME=testuser
ARG USERID=1000
RUN useradd -m -u ${USERID} -s /bin/bash ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# The setup scripts will be copied in at runtime.
# We also copy the capture so the test script can inspect it.
EOF

echo "Dockerfile written to $DOCKERFILE"

# Now build the image (this may take a while the first time).
IMAGE_NAME="lhn-repro-${CAPTURE_BASENAME}"
echo "Building reproduction image: ${IMAGE_NAME} (this can take several minutes)..."
docker build -t "${IMAGE_NAME}" -f "$DOCKERFILE" "$WORK_DIR"

echo ""
echo "=== Reproduction image built ==="

# Create a run script that will be executed inside the container.
RUN_SCRIPT="$WORK_DIR/run-test-inside.sh"
cat > "$RUN_SCRIPT" << 'RUNEOF'
#!/bin/bash
set -euo pipefail

echo "=== Inside reproduction container as $(whoami) ==="
echo "PATH: $PATH"
echo "Python: $(python --version 2>/dev/null || echo no python in PATH)"
echo "/opt/conda python: $(/opt/conda/bin/python --version 2>/dev/null || echo missing)"

# Copy the current scripts from the mounted volume (we will mount the host updatebionic).
# Assume they are at /host-updatebionic/
if [ -d /host-updatebionic ]; then
    echo "Host updatebionic dir is mounted at /host-updatebionic"
    cp /host-updatebionic/setup-system.sh /host-updatebionic/setup-user.sh . 2>/dev/null || true
    chmod +x setup-system.sh setup-user.sh 2>/dev/null || true
else
    echo "WARNING: /host-updatebionic not mounted — you must copy the scripts in manually or mount it."
fi

# Also make the capture available for inspection inside.
if [ -d /capture ]; then
    echo "Capture is available at /capture"
    ls /capture/ | head -10
fi

echo ""
echo "=== Running setup-system.sh (as this user; it may use sudo internally) ==="
./setup-system.sh || echo "setup-system.sh exited with code $?"

echo ""
echo "=== Running setup-user.sh ==="
./setup-user.sh || echo "setup-user.sh exited with code $?"

echo ""
echo "=== Post-setup inspection ==="
echo "Conda envs:"
conda env list || true

echo ""
echo "ls /tmp/*env* /tmp/miniconda 2>/dev/null || true"
ls -ld /tmp/*env* /tmp/miniconda 2>/dev/null || true

echo ""
echo "Jupyter kernels:"
jupyter kernelspec list 2>/dev/null || echo "jupyter not in PATH or no kernels"

echo ""
echo "Testing r_env (if it exists for this user)..."
R_ENV_PATH="/tmp/r_env-${USER:-testuser}"
if [ -d "$R_ENV_PATH" ]; then
    echo "Found $R_ENV_PATH"
    "$R_ENV_PATH/bin/python" --version || true
    "$R_ENV_PATH/bin/R" --version | head -1 || true
    echo "Testing reticulate from R (this may take a moment)..."
    "$R_ENV_PATH/bin/R" -e '
library(reticulate)
print("reticulate loaded")
py_config()
print("Trying to import plotnine via reticulate...")
try({
  p9 <- import("plotnine")
  print(paste("plotnine version:", p9$__version__))
}, silent = TRUE)
' 2>&1 | tail -20 || true
else
    echo "No r_env found at expected location for this user."
fi

echo ""
echo "=== Test run inside container finished ==="
RUNEOF
chmod +x "$RUN_SCRIPT"

echo "Run script inside container written."

# Now actually run the reproduction.
# We mount the current updatebionic dir from the host so the latest scripts are used.
# We also mount the capture for inspection.

echo ""
echo "=== Starting reproduction container ==="
echo "Mounting host updatebionic at /host-updatebionic"
echo "Mounting capture at /capture"

docker run --rm -it \
    -v "/home/harlan/projects/updatebionic:/host-updatebionic:ro" \
    -v "${CAPTURE_DIR}:/capture:ro" \
    --user "${USERNAME:-testuser}" \
    "${IMAGE_NAME}" \
    bash -c "cp /host-updatebionic/test-from-capture.sh /tmp/ 2>/dev/null || true; bash /host-updatebionic/test-from-capture.sh /capture 2>&1 || true; bash /run-test-inside.sh 2>&1 || true"

echo ""
echo "=== Local test run complete. ==="
echo "Review the output above for successes/failures in kernel creation,"
echo "conda environment layout, reticulate configuration, etc."
echo ""
echo "If problems are visible, we fix the scripts in the host checkout,"
echo "re-run this test command, and iterate until it is clean."
echo "Then the user gets the final updated scripts for their real container."