#!/bin/bash
# seed-from-captured-packs.sh
# Run *inside* the repro container.
# If /capture-packs/*.tar.gz exist, extract each to /tmp/<basename>/ and run conda-unpack.
# This lets us bring in "golden" entire envs captured from the real system
# (under whatever username suffix they had) for smoke-testing without re-solving.
set -euo pipefail

PACKS_MOUNT="/capture-packs"
if [ ! -d "$PACKS_MOUNT" ] || [ -z "$(ls $PACKS_MOUNT/*.tar.gz 2>/dev/null | head -1)" ]; then
    echo "No conda packs mounted at $PACKS_MOUNT — nothing to seed."
    exit 0
fi

echo "=== Seeding captured full conda environments from packs ==="
for pack in "$PACKS_MOUNT"/*.tar.gz; do
    bname=$(basename "$pack" .tar.gz)
    # All the interesting ones live under /tmp/ in these setups
    # (r_env-*, lhn_prod-*, lhn_dev-*, miniconda). /opt/conda is special.
    if [[ "$bname" == "conda" || "$bname" == "opt-conda" ]]; then
        target="/opt/conda"
    elif [[ "$bname" == "miniconda" ]]; then
        target="/tmp/miniconda"
    else
        target="/tmp/${bname}"
    fi

    echo ""
    echo "Seeding $bname from $pack -> $target"
    mkdir -p "$target"
    # conda-pack tarballs contain the prefix contents at the top level of the archive.
    if tar -xzf "$pack" -C "$target" --strip-components=0 2>/dev/null || \
       tar -xzf "$pack" -C "$target"; then
        echo "  Extracted."
    else
        echo "  WARNING: tar extract had issues; trying to proceed."
    fi

    if [ -x "$target/bin/conda-unpack" ]; then
        echo "  Running conda-unpack (relocates any absolute paths in the pack)..."
        "$target/bin/conda-unpack" || echo "  (conda-unpack returned non-zero; may still be usable)"
    else
        echo "  (no conda-unpack in this pack; the env may only work at the exact original prefix path)"
    fi

    # Quick sanity
    if [ -x "$target/bin/python" ]; then
        echo "  python in seeded env: $("$target/bin/python" --version 2>/dev/null || echo '?')"
    fi
    if [ -x "$target/bin/R" ]; then
        echo "  R in seeded env: $("$target/bin/R" --version 2>/dev/null | head -1 || echo '?')"
    fi
done

echo ""
echo "=== Seeding complete. Any /tmp/r_env-* /tmp/lhn_* /tmp/miniconda now present from capture. ==="
