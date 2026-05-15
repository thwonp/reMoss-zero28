#!/bin/bash
# Container-side build script for Tina Linux / Moss Zero28 firmware.
# Executed non-interactively by rebuild.sh, but can also be run directly
# inside an interactive container session for debugging.

set -e

cd /root/lichee

# 'source' is required here because lunch, add-rootfs-demo, and pack are
# shell functions defined by envsetup.sh, not standalone executables.
# Sourcing in the same process makes them available for the rest of this script.
source build/envsetup.sh

lunch a133_aw3-tina

export PATH="/root/lichee/lichee/arisc/ar100s/tools/toolchain/bin:$PATH"

cp /root/workspace/assets/configs/phase3-complete.config .config

bash /root/workspace/assets/install.sh

yes '' | make oldconfig

bash /root/workspace/assets/set-config.sh

make -j$(nproc)

add-rootfs-demo && pack
