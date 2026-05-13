#!/bin/bash
# Launch the Tina Linux / Moss build environment.
# Run this script from the host; it drops you into the container shell.
# The build tree and this repo are bind-mounted into the container.
#
# To resume after a disconnection (without --rm):
#   podman start -ai moss-build

set -e

SDK="/home/thwonp/Downloads/Zero 28 Linux_SDK/Stock SDK/lichee"
ASSETS="$(cd "$(dirname "$0")" && pwd)"

if ! podman image exists localhost/moss-build-env 2>/dev/null; then
    echo "Image not found — build it first:"
    echo "  cd $ASSETS && podman build -t moss-build-env ."
    exit 1
fi

# Remove any stopped container with the same name so we can start fresh
podman rm -f moss-build 2>/dev/null || true

exec podman run -it \
    --name moss-build \
    --security-opt label=disable \
    -v "$SDK:/root/lichee" \
    -v "$ASSETS:/root/workspace/assets" \
    localhost/moss-build-env
