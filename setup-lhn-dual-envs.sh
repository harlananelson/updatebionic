#!/bin/bash
# setup-lhn-dual-envs.sh
#
# Backward-compatible entry point. The setup is now split in two so that two
# users can share one node without colliding:
#
#   setup-system.sh  -- shared, machine-wide items (system libraries, Quarto,
#                       Miniconda, base-conda pip packages). Needs sudo. Run
#                       once per container boot; safe to run by either user
#                       (an flock + daily sentinel make re-runs a no-op).
#
#   setup-user.sh    -- per-user environments and Jupyter kernels. Every env,
#                       clone and cache path is suffixed with the username,
#                       so two people never fight over the same /tmp paths.
#
# This wrapper simply runs setup-user.sh, which in turn runs setup-system.sh
# automatically if the shared setup has not run today. Both users may run
# this; the result is per-user and safe.
#
# Usage:
#   ./setup-lhn-dual-envs.sh        # equivalent to ./setup-user.sh
#
# To pre-warm only the shared parts (e.g. the project lead, each morning):
#   ./setup-system.sh

set -eo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

USER_SCRIPT="$SCRIPT_DIR/setup-user.sh"
if [[ ! -f "$USER_SCRIPT" ]]; then
    echo "ERROR: $USER_SCRIPT not found."
    echo "This wrapper expects setup-user.sh and setup-system.sh alongside it."
    exit 1
fi

echo "setup-lhn-dual-envs.sh -> delegating to setup-user.sh (per-user setup)"
exec env -u SKIP_SELF_UPDATE bash "$USER_SCRIPT" "$@"
