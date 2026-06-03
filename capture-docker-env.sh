#!/bin/bash
#
# capture-docker-env.sh
#
# Run this *inside* the target Docker container (the one with the old conda + Spark setup).
# It will gather a comprehensive snapshot of the environment so that a matching
# test container can be recreated on the host Ubuntu machine for testing
# setup-system.sh and setup-user.sh.
#
# Usage inside the container:
#   chmod +x capture-docker-env.sh
#   ./capture-docker-env.sh
#
# It produces:
#   /tmp/env-capture-YYYYMMDD-HHMMSS.tar.gz
#
# Copy that tarball out of the container (e.g. docker cp or scp if possible)
# and send it back. Then we can use the captured specs to build a faithful
# reproduction here and test the dual-conda (old /opt/conda for pyspark 2.4.4
# + new /tmp/miniconda for modern R + Python r_env) Jupyter kernel setup.
#
# Safe to run as non-root; will note where sudo would be needed.
# Collects versions, paths, installed packages, conda info, python imports,
# jupyter kernels, spark config, mounts, user permissions, etc.
#
# Do not include secrets (no passwords, tokens, private keys).

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CAPTURE_DIR="/tmp/env-capture-${TIMESTAMP}"
TARBALL="${CAPTURE_DIR}.tar.gz"

echo "=== Starting environment capture at $(date) ==="
echo "Output will be in ${TARBALL}"

mkdir -p "${CAPTURE_DIR}"

log_cmd() {
    local name="$1"; shift
    echo "Capturing: $name"
    if "$@" > "${CAPTURE_DIR}/${name}.txt" 2>&1; then
        echo "  OK"
    else
        echo "  (command exited non-zero, output captured anyway)"
    fi
}

log_file() {
    local name="$1"; shift
    local f="$1"
    echo "Capturing file: $name ($f)"
    if [ -e "$f" ]; then
        cp -a "$f" "${CAPTURE_DIR}/${name}" 2>/dev/null || \
        cat "$f" > "${CAPTURE_DIR}/${name}.txt" 2>/dev/null || \
        ls -l "$f" > "${CAPTURE_DIR}/${name}-ls.txt" 2>/dev/null || true
    else
        echo "  (not found)" > "${CAPTURE_DIR}/${name}-missing.txt"
    fi
}

# Basic system identity
log_cmd "uname" uname -a
log_cmd "os-release" cat /etc/os-release
log_cmd "hostname" hostname
log_cmd "date" date
log_cmd "whoami" whoami
log_cmd "id" id
log_cmd "groups" groups

# Permissions / sudo capability (non-destructive check)
echo "Checking sudo capability (will not actually run privileged commands unless needed for ls)"
if sudo -n true 2>/dev/null; then
    echo "sudo available without password" > "${CAPTURE_DIR}/sudo-status.txt"
    log_cmd "sudo-id" sudo id
else
    echo "sudo requires password or not available for this user" > "${CAPTURE_DIR}/sudo-status.txt"
fi

# User home and work structure (common in these setups)
log_cmd "df" df -h
log_cmd "mount" mount
log_cmd "ls-home" ls -ld /home/* /root 2>/dev/null || true
log_cmd "ls-work" find / -maxdepth 4 -type d -name 'work' 2>/dev/null | head -20 || true
log_cmd "ls-persistent" ls -ld /persistent* /work* ~/work 2>/dev/null || true

# PATH and basic tools
echo "$PATH" > "${CAPTURE_DIR}/PATH.txt"
log_cmd "which-python" which python || true
log_cmd "which-R" which R || true
log_cmd "which-conda" which conda || true
log_cmd "python-version-system" python --version || true
log_cmd "python3-version" python3 --version || true
log_cmd "R-version" R --version || true
log_cmd "conda-version" conda --version || true

# Environment dump (redacted lightly)
env | sort > "${CAPTURE_DIR}/env.txt"
# Common interesting vars
for var in PATH PYTHONPATH SPARK_HOME HADOOP_CONF_DIR CONDA_PREFIX CONDA_DEFAULT_ENV JAVA_HOME; do
    echo "$var=${!var:-<unset>}" >> "${CAPTURE_DIR}/key-env-vars.txt"
done

# Jupyter / kernels
log_cmd "jupyter-version" jupyter --version || true
log_cmd "jupyter-kernelspecs" jupyter kernelspec list || true
log_cmd "jupyter-kernelspecs-json" jupyter kernelspec list --json || true

# The critical old conda at /opt/conda
if [ -d /opt/conda ]; then
    echo "Found /opt/conda"
    log_cmd "opt-conda-version" /opt/conda/bin/conda --version
    log_cmd "opt-conda-python-version" /opt/conda/bin/python --version
    log_cmd "opt-conda-python-sys" /opt/conda/bin/python -c "
import sys
print('Python:', sys.version)
print('Executable:', sys.executable)
print('Prefix:', sys.prefix)
print('First 8 sys.path:')
for p in sys.path[:8]: print(' ', p)
" 
    log_cmd "opt-conda-pyspark-check" /opt/conda/bin/python -c "
import sys
print('Python:', sys.version)
try:
    import pyspark
    print('pyspark version:', pyspark.__version__)
    print('pyspark location:', pyspark.__file__)
except Exception as e:
    print('pyspark import failed:', type(e).__name__, str(e)[:200])
try:
    import pandas
    print('pandas version:', pandas.__version__)
except Exception as e:
    print('pandas import failed:', type(e).__name__, str(e)[:200])
" 
    log_cmd "opt-conda-list-pyspark-pandas" /opt/conda/bin/conda list | grep -E 'pyspark|pandas|numpy|python' || true
    log_cmd "opt-conda-info" /opt/conda/bin/conda info || true
    # Don't dump the entire env (too big); capture key files
    ls -l /opt/conda/bin/python* /opt/conda/bin/conda* > "${CAPTURE_DIR}/opt-conda-bin-key.txt" 2>/dev/null || true
else
    echo "/opt/conda NOT FOUND" > "${CAPTURE_DIR}/opt-conda-missing.txt"
fi

# System /usr/local/spark (very common in these LHN setups)
if [ -d /usr/local/spark ]; then
    log_cmd "usr-local-spark-ls" ls -ld /usr/local/spark /usr/local/spark/python*
    log_cmd "usr-local-spark-pyspark-version" python -c "
import sys
sys.path.insert(0, '/usr/local/spark/python')
import pyspark
print('pyspark from /usr/local/spark:', pyspark.__version__)
print('location:', pyspark.__file__)
" 2>&1 || true
    # Capture the cloudpickle file that often causes the bytes error
    log_file "cloudpickle-py" /usr/local/spark/python/pyspark/cloudpickle.py
    log_cmd "spark-version" cat /usr/local/spark/RELEASE 2>/dev/null || cat /usr/local/spark/VERSION 2>/dev/null || echo "no VERSION file"
else
    echo "/usr/local/spark NOT FOUND" > "${CAPTURE_DIR}/usr-local-spark-missing.txt"
fi

# Check for existing /tmp/miniconda (the "updated" one we install)
if [ -d /tmp/miniconda ]; then
    log_cmd "tmp-miniconda-version" /tmp/miniconda/bin/conda --version
    log_cmd "tmp-miniconda-python-version" /tmp/miniconda/bin/python --version
else
    echo "/tmp/miniconda NOT PRESENT (expected in a fresh or pre-setup container)" > "${CAPTURE_DIR}/tmp-miniconda-absent.txt"
fi

# Existing r_env or lhn envs (if any)
for envpath in /tmp/r_env* /tmp/lhn_*; do
    if [ -d "$envpath" ]; then
        base=$(basename "$envpath")
        log_cmd "${base}-python-version" "$envpath/bin/python" --version || true
        log_cmd "${base}-R-version" "$envpath/bin/R" --version || true
        echo "$envpath" >> "${CAPTURE_DIR}/existing-envs.txt"
    fi
done

# Apt / system packages (very useful for recreating the base image)
log_cmd "apt-list-installed" apt list --installed 2>/dev/null || dpkg -l
log_cmd "dpkg-python-spark" dpkg -l | grep -E 'python|spark|jupyter|conda' || true

# Key directories listing (not full recursive to keep size reasonable)
log_cmd "ls-opt" ls -ld /opt/* 2>/dev/null || true
log_cmd "ls-tmp" ls -ld /tmp/* 2>/dev/null | head -30 || true
log_cmd "ls-usr-local" ls -ld /usr/local/* 2>/dev/null || true

# Jupyter config / kernels dir
log_cmd "ls-jupyter-config" ls -lR /etc/jupyter /root/.jupyter ~/.jupyter 2>/dev/null || true
log_cmd "ls-kernels" find / -name 'kernel.json' 2>/dev/null | head -20 || true

# Any existing setup logs in the project (if the updatebionic is mounted)
if [ -d ~/updatebionic/logs ] || [ -d /updatebionic/logs ]; then
    log_cmd "existing-setup-logs" find / -path '*/updatebionic/logs/*' -name '*.log' 2>/dev/null | head -10 || true
fi

# Capture current setup-user.sh / setup-system.sh if they are present in the container
for f in setup-user.sh setup-system.sh setup-lhn-dual-envs.sh; do
    for loc in . ~/updatebionic /updatebionic /home/*/updatebionic; do
        if [ -f "$loc/$f" ]; then
            cp "$loc/$f" "${CAPTURE_DIR}/container-${f}" 2>/dev/null || true
            break
        fi
    done
done

# Final tarball
echo "Creating tarball..."
tar -czf "${TARBALL}" -C /tmp "env-capture-${TIMESTAMP}"

echo ""
echo "=== Capture complete ==="
echo "Tarball: ${TARBALL}"
echo "Size: $(du -h "${TARBALL}" | cut -f1)"
echo ""
echo "Please copy this file out of the container and send it back."
echo "Example (from host, if you have docker access):"
echo "  docker cp <container-name-or-id>:${TARBALL} ."
echo ""
echo "Then we can recreate a matching container locally and test the scripts."
echo "=== End of capture script ==="# Additional useful dumps
log_cmd "conda-env-list" conda env list || true
log_cmd "pip-list-opt-conda" /opt/conda/bin/pip list 2>/dev/null || true
log_cmd "pip-list-if-miniconda" /tmp/miniconda/bin/pip list 2>/dev/null || true

# Capture the exact setup scripts that are currently in the container (for version comparison)
for script in setup-system.sh setup-user.sh setup-lhn-dual-envs.sh add-r-kernel.sh; do
    for searchdir in / /home /tmp /work* ~/updatebionic /updatebionic; do
        if [ -f "${searchdir}/${script}" ]; then
            cp "${searchdir}/${script}" "${CAPTURE_DIR}/container-current-${script}" 2>/dev/null && echo "Captured container's ${script}" || true
            break
        fi
    done
done

# If the updatebionic repo is checked out, capture its current git status
for repodir in ~/updatebionic /updatebionic /home/*/updatebionic; do
    if [ -d "${repodir}/.git" ]; then
        (cd "${repodir}" && git status --porcelain > "${CAPTURE_DIR}/updatebionic-git-status.txt" 2>/dev/null; git log -1 --oneline > "${CAPTURE_DIR}/updatebionic-git-log.txt" 2>/dev/null) || true
        break
    fi
done

echo "Capture finished at $(date)"
