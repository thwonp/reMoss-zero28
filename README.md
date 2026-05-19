# Moss for the MagicX Zero 28

Custom Moss (Tina Linux) firmware for the MagicX Mini Zero 28 (Allwinner A133P). Adds hardware framebuffer rotation, NextUI-compatible SDL2 runtime, and a clean package selection. Does not contain proprietary Allwinner source.

---

## Prerequisites

**SDK archive** — the proprietary Tina Linux source. Must be at:
```
~/Downloads/Zero 28 Linux_SDK/Archive/mplus_a133_tina_v1.0.tar.gz
```
If split into parts, reassemble with `cat` before use.

**BSP patches** — from the Framebuffer Rotation package provided alongside the SDK. See [patches/ setup](#patches-setup) below.

**podman** — used to run the build container. `docker` will also work with minor script edits.

**OpenixCard** — converts the proprietary Allwinner `.img` to a raw flashable image.
Install: https://github.com/YuzukiTsuru/OpenixCard

On Fedora, also install the runtime dependency:
```bash
sudo dnf install -y libconfuse
```

---

## One-time setup

### 1. Build the container image

```bash
podman build -t moss-build-env .
```

### 2. patches/ setup

`patches/` is gitignored. Copy the BSP patch files from the SDK before building:

```bash
SDK_ROT=~/Downloads/Zero\ 28\ Linux_SDK/Framebuffer\ Rotation

cp "$SDK_ROT/a133-tina-bsp-update-2025-10-11/lichee/linux-4.9/"0001-*.patch \
   patches/

cp "$SDK_ROT/zero28-patch/a133_g2d_90_270_rot.patch" \
   patches/0002-zero28-g2d-90-270-rot-fix.patch

cp "$SDK_ROT/a133-tina-bsp-update-2025-10-11/lichee/brandy-2.0/u-boot-2018/"0001-*.patch \
   patches/

# Three custom patches must also be present before building.
# These are not included in the SDK or this repository:
#   patches/006-lazy-g2d-open.patch
#   patches/008-remove-init-apply.patch
#   patches/012-fix-copy-boot-fb-skip-rotation.patch
```

---

## Building

### Normal build (SDK already extracted)

```bash
# host
./build-env.sh

# container
cd /root/lichee
source build/envsetup.sh && lunch   # select 3 (a133_aw3-tina)
. /root/workspace/assets/build-inner.sh
make -j$(nproc) && add-rootfs-demo && pack
```

`build-inner.sh` stops before `make` and prints the command. Source it with `.`, not `bash`.

### Clean build (restore SDK from tarball)

```bash
# host — exit any running build container first
./rebuild.sh --clean
./build-env.sh
# then continue with container steps above
```

`rebuild.sh --clean` wipes the SDK, re-extracts from the tarball, and preserves `dl/` (the downloaded GCC 7.4.1 toolchain; not in the tarball).

### Resume a disconnected container

```bash
podman start -ai moss-build
```

---

## Output and flashing

The packed image is at:
```
~/Downloads/Zero 28 Linux_SDK/Stock SDK/lichee/out/a133-aw3/tina_a133-aw3_uart0.img
```

Convert to a raw flashable image:
```bash
cd ~/Downloads/Zero\ 28\ Linux_SDK/Stock\ SDK/lichee/out/a133-aw3/
OpenixCard -d tina_a133-aw3_uart0.img
```

Flash (do not pull the card until the activity light stops):
```bash
sudo dd if=<output from OpenixCard> of=/dev/sdX bs=4M conv=fsync status=progress
```

---

## Boot logo

File: `bootlogo.bmp`
- Format: BMP, 24-bit, no compression
- Max width: 480px (u-boot framebuffer is 480×640 — images wider than this are silently rejected)
- Orientation: pre-rotated 90° CCW (u-boot applies 90° CW hardware rotation; content must be stored CCW-rotated to appear landscape on screen)

---

## Reference

See `notes.md` for details on what `install.sh` does, the container scripts, and the full package enable/disable list in `moss-tina.config`.
