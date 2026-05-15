#!/bin/bash
# Host-side build prep for Tina Linux / Moss Zero28 firmware.
# Run from the host.
#
# Usage: ./rebuild.sh [--clean]
#
# (no flag)  Print next-step instructions.
# --clean    Wipe and restore the SDK from tarball first, then print instructions.
#            IMPORTANT: Exit any running build container before using --clean.
#            Removing the SDK while a container is bind-mounting it leaves
#            the container's /root/lichee/ stale.

set -e

SDK="/home/thwonp/Downloads/Zero 28 Linux_SDK/Stock SDK/lichee"
SDK_TAR="$HOME/Downloads/Zero 28 Linux_SDK/Archive/mplus_a133_tina_v1.0.tar.gz"
ASSETS="$(cd "$(dirname "$0")" && pwd)"

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
    echo "NOTE: Exit any active build container before continuing."
    echo ""

    if [ ! -f "$SDK_TAR" ]; then
        echo "Error: SDK tarball not found at: $SDK_TAR"
        exit 1
    fi

    SDK_PARENT="$(dirname "$SDK")"
    TMPDIR_DL="$(mktemp -d)"

    # Preserve dl/ (contains linaro-7.4 toolchain; not in tarball).
    # podman unshare: build artifacts may be owned by subuid-mapped uids
    # that the host user cannot read/remove directly.
    if [ -d "$SDK/dl" ]; then
        echo "Preserving dl/ ..."
        podman unshare cp -a "$SDK/dl" "$TMPDIR_DL/"
    fi

    echo "Removing old SDK ..."
    podman unshare rm -rf "$SDK"

    echo "Extracting tarball ..."
    tar -xf "$SDK_TAR" -C "$SDK_PARENT"

    if [ -d "$TMPDIR_DL/dl" ]; then
        echo "Restoring dl/ ..."
        podman unshare cp -a "$TMPDIR_DL/dl" "$SDK/"
    fi

    podman unshare rm -rf "$TMPDIR_DL"
    echo "--- SDK restore complete ---"
    echo ""
fi

if ! podman image exists localhost/moss-build-env 2>/dev/null; then
    echo "WARNING: Container image not found. Build it first:"
    echo "  podman build -t moss-build-env $ASSETS"
    echo ""
fi

echo "SDK ready. To build:"
echo "  1. $ASSETS/build-env.sh"
echo "  2. Inside the container:"
echo "       cd /root/lichee"
echo "       source build/envsetup.sh && lunch   # select 3 (a133_aw3-tina)"
echo "       . /root/workspace/assets/build-inner.sh"
