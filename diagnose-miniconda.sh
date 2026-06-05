#!/bin/bash
# diagnose-miniconda.sh
#
# Standalone diagnostic for the Part 3 "Install Miniconda" failure in
# setup-system.sh. The LHN Docker container is rebuilt every day, so
# /tmp/miniconda is wiped each morning and Part 3 runs the full Miniconda
# DOWNLOAD + INSTALL every day. In setup-system.sh that download is
# `wget -q ...` under `set -eo pipefail`, so any failure aborts the whole
# script SILENTLY (and setup-user.sh then mislabels it as a sudo/apt error).
#
# This script reproduces ONLY the download/install step, with all output
# visible, and records everything to a timestamped log file so the failure
# can be inspected after the fact. It is read-only with respect to the real
# environment: it installs (if it gets that far) into a THROWAWAY prefix
# under /tmp and removes it, so it never touches /tmp/miniconda.
#
# Usage:
#   chmod +x diagnose-miniconda.sh
#   ./diagnose-miniconda.sh
#
# The log is written to: logs/diagnose-miniconda-<timestamp>.log
# (relative to this script). Commit/push that log back so it can be reviewed.

# NOTE: deliberately NOT using `set -e` here — a diagnostic must keep running
# past failures so it can report every check, not stop at the first one.
set -o pipefail

# ========== Same values setup-system.sh Part 3 uses ==========
MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py310_23.11.0-2-Linux-x86_64.sh"
MINICONDA_PATH="/tmp/miniconda"          # the real shared prefix (we do NOT touch it)
HOSTPART="repo.anaconda.com"

# ========== Log file setup ==========
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/diagnose-miniconda-$STAMP.log"

# Send everything (stdout + stderr) to the console AND the log file.
exec > >(tee -a "$LOG_FILE") 2>&1

section() { echo ""; echo "========== $* =========="; }
note()    { echo "  $*"; }

echo "##############################################################"
echo "# Miniconda Part 3 diagnostic"
echo "# Started: $(date)"
echo "# Log file: $LOG_FILE"
echo "##############################################################"

# ========== 1. Host / OS / user ==========
section "1. Host, OS and user"
note "whoami      : $(whoami)"
note "hostname    : $(hostname 2>/dev/null)"
note "uname -a    : $(uname -a 2>/dev/null)"
if [ -r /etc/os-release ]; then
    note "os-release  : $(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '\"')"
fi
note "GLIBC       : $(ldd --version 2>/dev/null | head -1)"
note "  (Miniconda 23.11.0-2 is pinned for Ubuntu 18.04 GLIBC 2.27 compatibility)"

# ========== 2. /tmp state and free space ==========
section "2. /tmp state and disk space"
if [ -d "$MINICONDA_PATH" ]; then
    note "$MINICONDA_PATH EXISTS — owner/perm: $(ls -ld "$MINICONDA_PATH")"
    note "  (in the real run Part 3 would SKIP install; today it apparently did not, so it was absent)"
else
    note "$MINICONDA_PATH does NOT exist — Part 3 would attempt a full download+install (expected on a fresh daily container)."
fi
note "Free space on /tmp:"
df -h /tmp 2>&1 | sed 's/^/    /'

# ========== 3. Proxy / network environment ==========
section "3. Proxy and network environment variables"
for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY ALL_PROXY; do
    eval "val=\${$v:-}"
    if [ -n "$val" ]; then note "$v = $val"; else note "$v = (unset)"; fi
done

# ========== 4. DNS resolution ==========
section "4. DNS resolution of $HOSTPART"
if command -v getent >/dev/null 2>&1; then
    getent hosts "$HOSTPART" 2>&1 | sed 's/^/    /' || note "getent could not resolve $HOSTPART"
elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$HOSTPART" 2>&1 | sed 's/^/    /'
else
    note "no getent/nslookup available to test DNS"
fi

# ========== 5. HTTPS reachability (headers only) ==========
section "5. HTTPS reachability — HEAD request to the Miniconda URL"
if command -v curl >/dev/null 2>&1; then
    note "Using curl -sSIL (follow redirects, show status):"
    curl -sSIL --max-time 60 "$MINICONDA_URL" 2>&1 | sed 's/^/    /'
    note "curl exit code: $?"
else
    note "curl not available; trying wget --spider:"
    wget --spider -S --timeout=60 "$MINICONDA_URL" 2>&1 | sed 's/^/    /'
    note "wget --spider exit code: $?"
fi

# ========== 6. Actual download (the real failure point) ==========
section "6. Actual download attempt (this is what Part 3 does, but NOT quiet)"
TMP_INSTALLER="/tmp/diagnose-miniconda-$STAMP.sh"
note "Downloading to $TMP_INSTALLER ..."
note "Command: wget --timeout=120 --tries=2 -O \"$TMP_INSTALLER\" \"$MINICONDA_URL\""
wget --timeout=120 --tries=2 -O "$TMP_INSTALLER" "$MINICONDA_URL"
WGET_RC=$?
note "wget exit code: $WGET_RC  (0 = success; non-zero = THIS is why Part 3 aborts silently with wget -q)"

DOWNLOAD_OK=0
if [ -f "$TMP_INSTALLER" ]; then
    SIZE=$(stat -c '%s' "$TMP_INSTALLER" 2>/dev/null || wc -c < "$TMP_INSTALLER")
    note "Downloaded file size: ${SIZE} bytes"
    note "  (a healthy Miniconda3-py310_23.11.0-2 installer is roughly 130 MB / ~130000000 bytes)"
    note "First 3 lines of the downloaded file (should look like a shell installer header):"
    head -3 "$TMP_INSTALLER" 2>&1 | sed 's/^/    /'
    # An HTML error page or an empty/truncated file means the CDN/proxy returned something bad.
    if head -1 "$TMP_INSTALLER" 2>/dev/null | grep -qi '<html\|<!doctype'; then
        note "WARNING: file looks like an HTML page, not an installer — proxy/CDN likely returned an error page."
    fi
    if [ "${SIZE:-0}" -gt 50000000 ] && [ "$WGET_RC" -eq 0 ]; then
        DOWNLOAD_OK=1
    fi
else
    note "No file was created — download failed outright."
fi

# ========== 7. Installer dry-run into a THROWAWAY prefix ==========
section "7. Installer execution into a throwaway prefix (only if download looked OK)"
THROWAWAY="/tmp/diagnose-miniconda-prefix-$STAMP"
if [ "$DOWNLOAD_OK" -eq 1 ]; then
    note "Running: bash \"$TMP_INSTALLER\" -b -p \"$THROWAWAY\""
    note "(This mirrors Part 3's install line; prefix is a throwaway, NOT the real /tmp/miniconda.)"
    bash "$TMP_INSTALLER" -b -p "$THROWAWAY"
    INSTALL_RC=$?
    note "installer exit code: $INSTALL_RC"
    if [ "$INSTALL_RC" -eq 0 ] && [ -x "$THROWAWAY/bin/conda" ]; then
        note "conda version in throwaway prefix:"
        "$THROWAWAY/bin/conda" --version 2>&1 | sed 's/^/    /'
        note "SUCCESS: download + install both work. The daily failure was likely transient."
    else
        note "FAILURE: installer did not produce a working conda — see exit code/output above."
    fi
else
    note "Skipped installer test because the download did not produce a plausible installer."
    note "==> The failure is in the DOWNLOAD step (network/proxy/CDN), not the installer."
fi

# ========== 8. Cleanup (never touch the real /tmp/miniconda) ==========
section "8. Cleanup"
rm -f "$TMP_INSTALLER"   && note "removed $TMP_INSTALLER"
rm -rf "$THROWAWAY"      && note "removed $THROWAWAY"
note "The real $MINICONDA_PATH was never modified by this diagnostic."

# ========== Verdict ==========
section "Verdict"
if [ "$DOWNLOAD_OK" -eq 1 ]; then
    echo "  Download succeeded. If the daily setup still fails here, capture this log on a"
    echo "  morning when it actually fails — the problem is intermittent."
else
    echo "  Download FAILED. Part 3 of setup-system.sh uses 'wget -q' under 'set -eo pipefail',"
    echo "  so this same failure aborts the whole setup with no message. Review sections 3-6"
    echo "  above (proxy vars, DNS, HTTPS HEAD, wget exit code) to see exactly why."
fi
echo ""
echo "Finished: $(date)"
echo "Log saved to: $LOG_FILE"
