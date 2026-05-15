#!/bin/bash
# Automated build wrapper for Tina Linux / Moss Zero28 firmware.
# Run this script from the host.
#
# Usage: ./rebuild.sh [--clean]
#
# --clean: Wipes and restores the SDK from the tarball before building.
#          IMPORTANT: Exit any running build container before using --clean.
#          Removing the SDK while a container is bind-mounting it leaves
#          the container's /root/lichee/ stale.

set -e

SDK="/home/thwonp/Downloads/Zero 28 Linux_SDK/Stock SDK/lichee"
SDK_TAR="$HOME/Downloads/Zero 28 Linux_SDK/Archive/mplus_a133_tina_v1.0.tar.gz"
ASSETS="$(cd "$(dirname "$0")" && pwd)"

if ! podman image exists localhost/moss-build-env 2>/dev/null; then
    echo "Image not found — build it first:"
    echo "  cd $ASSETS && podman build -t moss-build-env ."
    exit 1
fi

# Parse arguments
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --clean)
            CLEAN=1
            ;;
        *)
            echo "Unknown flag: $arg"
            echo "Usage: $0 [--clean]"
            exit 1
            ;;
    esac
done

if [ "$CLEAN" -eq 1 ]; then
    echo "--- Clean restore: wiping SDK and re-extracting from tarball ---"
    echo "NOTE: If you have an active build container open, exit it first."
    echo "      Removing the SDK while a container is bind-mounting it will"
    echo "      leave that container's /root/lichee/ stale."
    echo ""

    if [ ! -f "$SDK_TAR" ]; then
        echo "Error: SDK tarball not found at: $SDK_TAR"
        exit 1
    fi

    SDK_PARENT="$(dirname "$SDK")"
    TMPDIR_DL="$(mktemp -d)"

    # Preserve dl/ (contains linaro-7.4 toolchain; not in tarball)
    if [ -d "$SDK/dl" ]; then
        echo "Preserving dl/ ..."
        cp -a "$SDK/dl" "$TMPDIR_DL/"
    fi

    echo "Removing old SDK ..."
    rm -rf "$SDK"

    echo "Extracting tarball ..."
    tar -xf "$SDK_TAR" -C "$SDK_PARENT"

    # Restore dl/ into freshly extracted SDK
    if [ -d "$TMPDIR_DL/dl" ]; then
        echo "Restoring dl/ ..."
        cp -a "$TMPDIR_DL/dl" "$SDK/"
    fi

    rm -rf "$TMPDIR_DL"
    echo "--- SDK restore complete ---"
    echo ""
fi

exec podman run --rm \
    --security-opt label=disable \
    -v "$SDK:/root/lichee" \
    -v "$ASSETS:/root/workspace/assets" \
    localhost/moss-build-env \
    /bin/bash /root/workspace/assets/build-inner.sh
