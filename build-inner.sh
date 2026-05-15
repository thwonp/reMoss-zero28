#!/bin/bash
# Container-side build script for Tina Linux / Moss Zero28 firmware.
#
# IMPORTANT: Source this script, do not run it with bash.
# bash creates a subshell that cannot inherit shell functions from the parent.
#
# Required setup before sourcing:
#   cd /root/lichee
#   source build/envsetup.sh
#   lunch                    # select 3 (a133_aw3-tina)
#
# Then run:
#   . /root/workspace/assets/build-inner.sh
#
# The body runs inside a subshell ( ) so set -e failures exit only the build,
# not your interactive container session.

(
set -e
trap 'echo "[build-inner.sh] FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR

cd /root/lichee

# Verify lunch was run before sourcing this script.
for fn in add-rootfs-demo pack; do
    if ! type "$fn" &>/dev/null; then
        echo "[build-inner.sh] ERROR: '$fn' not defined." >&2
        echo "  Run first: source build/envsetup.sh && lunch (select 3)" >&2
        exit 1
    fi
done
echo "[build-inner.sh] Build environment OK (lunch already run)"

export PATH="/root/lichee/lichee/arisc/ar100s/tools/toolchain/bin:$PATH"

echo "[build-inner.sh] Copying phase3-complete.config to .config ..."
cp /root/workspace/assets/configs/phase3-complete.config .config
echo "[build-inner.sh] Config copied — $(wc -l < .config) lines"

echo "[build-inner.sh] Running install.sh ..."
bash /root/workspace/assets/install.sh

echo "[build-inner.sh] --- Patch verification ---"
_ok() { echo "  [OK]   $1"; }
_fail() { echo "  [FAIL] $1" >&2; }

# Board defconfig: Phase II toolchain
grep -q 'linaro-7.4' target/allwinner/a133-aw3/defconfig \
    && _ok "Board defconfig: GCC 7.4 toolchain" \
    || _fail "Board defconfig: GCC 7.4 toolchain NOT patched"

# Board defconfig: NSS/NSPR negated (would pull in unwanted packages)
grep -q '# CONFIG_PACKAGE_nspr is not set' target/allwinner/a133-aw3/defconfig \
    && _ok "Board defconfig: nspr negated" \
    || _fail "Board defconfig: nspr NOT negated"

# DTS: rotation degree and dimensions
grep -q 'degree0' device/config/chips/a133/configs/aw3/board.dts \
    && _ok "DTS: degree0 present" \
    || _fail "DTS: degree0 missing"
grep -q 'disp_rotation_used' device/config/chips/a133/configs/aw3/board.dts \
    && _ok "DTS: disp_rotation_used present" \
    || _fail "DTS: disp_rotation_used missing"
grep -q 'fb0_width.*640' device/config/chips/a133/configs/aw3/board.dts \
    && _ok "DTS: fb0_width=640" \
    || _fail "DTS: fb0_width not 640"

# Kernel defconfig: HW rotation support
grep -q 'SUNXI_DISP2_FB_HW_ROTATION_SUPPORT=y' lichee/linux-4.9/arch/arm64/configs/sun50iw10p1smp_defconfig \
    && _ok "Kernel defconfig: HW rotation enabled" \
    || _fail "Kernel defconfig: HW rotation missing"

# Kernel source: dev_fb.c 90/270 dimension swap
grep -q 'degree_int == 1 || degree_int == 3' lichee/linux-4.9/drivers/video/fbdev/sunxi/disp2/disp/dev_fb.c \
    && _ok "Kernel: dev_fb.c 90/270 dimension swap patched" \
    || _fail "Kernel: dev_fb.c patch missing"

# Cairo mutex fix
grep -q 'CAIRO_NO_MUTEX' package/gui/libs/cairo/Makefile \
    && _ok "Cairo: CAIRO_NO_MUTEX fix applied" \
    || _fail "Cairo: CAIRO_NO_MUTEX fix missing"

unset -f _ok _fail
echo "[build-inner.sh] --- End verification ---"

echo "[build-inner.sh] Running make oldconfig ..."
yes '' | make oldconfig

echo "[build-inner.sh] Running set-config.sh ..."
bash /root/workspace/assets/set-config.sh

echo "[build-inner.sh] Verifying toolchain in .config after set-config ..."
grep 'CONFIG_GCC_VERSION=' .config | head -1

echo ""
echo "Build environment ready. Run:"
echo "  make -j\$(nproc) && add-rootfs-demo && pack"
)
