# Moss Zero28 — Build Notes

---

## Scripts

| Script | Runs on | Purpose |
|--------|---------|---------|
| `rebuild.sh [--clean]` | host | Restores SDK from tarball (--clean) and prints next-step instructions. Preserves `dl/` across wipes. |
| `build-env.sh` | host | Launches the build container. Bind-mounts SDK → `/root/lichee`, this repo → `/root/workspace/assets`. |
| `build-inner.sh` | container | Full build setup: copy config, run install.sh, verify patches, oldconfig, set-config.sh, then print the make command. Source with `.`, not `bash`. |
| `install.sh` | container | Idempotent SDK patcher. See below. |
| `set-config.sh` | container | Overlays `moss-tina.config` onto the normalized `.config`. Run after `yes '' \| make oldconfig`. |
| `Containerfile` | host (build) | Ubuntu 18.04 image with all Tina build deps, xxd, i386 libs, and the arisc or32-elf toolchain in PATH. |

---

## Build sequence (normal)

```
# host
./rebuild.sh                    # or --clean to restore SDK from tarball first
./build-env.sh                  # drops into container

# container
cd /root/lichee
source build/envsetup.sh && lunch   # select 3 (a133_aw3-tina)
. /root/workspace/assets/build-inner.sh
make -j$(nproc) && add-rootfs-demo && pack
```

`build-inner.sh` stops before `make` and prints the command — run it manually.

---

## patches/ setup (required once per fresh SDK)

`patches/` is gitignored. Copy from the SDK before building:

```bash
SDK_ROT=~/Downloads/Zero\ 28\ Linux_SDK/Framebuffer\ Rotation

cp "$SDK_ROT/a133-tina-bsp-update-2025-10-11/lichee/linux-4.9/"0001-*.patch \
   ~/opencode/git/Moss-zero28/patches/

cp "$SDK_ROT/zero28-patch/a133_g2d_90_270_rot.patch" \
   ~/opencode/git/Moss-zero28/patches/0002-zero28-g2d-90-270-rot-fix.patch

cp "$SDK_ROT/a133-tina-bsp-update-2025-10-11/lichee/brandy-2.0/u-boot-2018/"0001-*.patch \
   ~/opencode/git/Moss-zero28/patches/
```

---

## What install.sh does

install.sh is safe to re-run (all edits are guarded). It applies:

**Kernel / u-boot patches**
- `0001-feat-support-disp2-fb-hw-rotate.patch` — disp2 framebuffer HW rotation support
- `0001-feat-support-fb-bootlogo-rotate.patch` — u-boot boot logo rotation (already present in stock SDK; patch is a no-op but harmless)
- `0002-zero28-g2d-90-270-rot-fix.patch` — applied as sed/python (patch context mismatches BSP output)
- `006-lazy-g2d-open.patch` — moves g2d_open() into fb_g2d_rot_apply() (lazy open);
  fixes fb_g2d_rot_free() to only release if opened; corrects clip_rect w/h swap
- `008-remove-init-apply.patch` — removes the init-time fb_g2d_rot apply() call from
  display_fb_request() in dev_fb.c; apply() is correctly called per-frame from fb_pan_display()
- `012-fix-copy-boot-fb-skip-rotation.patch` — skips the CPU rotation copy in
  Fb_copy_boot_fb() when degree_int != 0; with G2D active the copy is redundant and hangs
- `dev_fb.c` dimension swap for 90°/270° G2D blits
- `fb_g2d_rot.c` width/height swap and rotation direction fix

All patches are applied via the `apply_patch()` helper (defined in install.sh): dry-runs
first; prints INFO and skips if already applied; prints WARN and applies if hunks fail;
applies cleanly otherwise. Replaces the old `patch -N -p1 < ... || true` pattern.

**DTS edits** (`device/config/chips/a133/configs/aw3/board.dts`)
- `disp_rotation_used = <1>`, `degree0 = <1>` (90° CW hardware rotation)

**Kernel defconfig** (`sun50iw10p1smp_defconfig`) — Note: the arch defconfig is NOT the
active path under Tina; the real sources of truth are `config-4.9` (clean builds) and
`scripts/config` (incremental). The arch defconfig is also patched but is unused by the
Tina build system.
- `CONFIG_SUNXI_DISP2_FB_HW_ROTATION_SUPPORT=y`
- NLS ISO 8859-1, NLS UTF-8, FAT default iocharset=utf8

**XR829 WiFi kernel config** (`config-4.9` + `scripts/config`)
- `CONFIG_XR829_WLAN=y` — top-level gate (bool, stays built-in)
- `CONFIG_XRADIO=m` — SDIO driver as module (=y conflicts with built-in mac80211)
- `CONFIG_XRMAC=m` — XRMAC is a mac80211 fork; both =y causes ieee80211_* linker errors
- `CONFIG_XRADIO_SDIO=y` — SDIO bus binding (bool)

**Toolchain** (`target/allwinner/a133-aw3/defconfig`)
- Patches board defconfig to GCC 7.4.1 / binutils 2.28 / glibc 2.29
- Syncs board defconfig with `moss-tina.config` (package selections survive Tina's `.config` overwrite at build time)

**GCC 7 / glibc 2.29 build fixes**
- `e2fsprogs`: `-include sys/sysmacros.h -D_GNU_SOURCE` (makedev, stat64, GNU extensions)
- `netifd`: `-Wno-error=format-truncation`
- `libcedarc/libcedarx`: `-Wno-error=format-truncation`, `-Wno-error=nonnull`
- `ffmpeg`: strips `libAWIspApi` deps, adds `--disable-indevs`
- `cairo`: `CAIRO_NO_MUTEX=1` (pthreads detection fails under GCC 7 cross-compile)
- `fontconfig`: OpenWrt-style patch for `PRI_CHAR_WIDTH_STRONG` undeclared

**Removed packages** (fail to build; not needed on Zero28)
- `camerademo`, `trecorderdemo` — link `libisp.so` which uses `major()`/`minor()` as function symbols absent in glibc 2.29
- `resample` — `libc.so` missing dep; `libsamplerate` covers resampling

**Other**
- Boot-resource partition increased to 2048 sectors (640×480 logo requires it)
- Broken thirdparty IoT packages removed (cause OpenWrt scanner errors)
- `etc/rc.local`, `etc/banner`, `usr/` overlaid into rootfs
- `bootlogo.bmp` copied to boot-resource

---

## moss-tina.config — package selections

### Kept for NextUI + Portmaster

| Package | Reason |
|---------|--------|
| `busybox` (unzip) | archive extraction |
| `libflac`, `fdk-aac`, `libopus`, `ffmpeg`, `x264`, `libsamplerate` | audio/video playback |
| `curl`, `libgnutls` | Portmaster HTTPS downloads |
| `python3` | Portmaster scripts |
| `wpa-supplicant`, `wpa-cli` | WiFi |
| `kmod-cfg80211` | base WiFi framework |
| Target Images → downsize kernel (EXPERIMENTAL) | boot time |

### Disabled — GUI / Allwinner apps

| Package | Reason |
|---------|--------|
| Qt5 (`ococci-launcher`, `ococci-daemon`, all Qt) | replaced by NextUI |
| Minigui + samples | not needed |
| libcairo, libchipmunk, libpixman | GUI libs not used by NextUI |
| btmanager, btmanager-demo | BT manager app; NextUI handles BT directly |
| smartlinkd | Allwinner IoT provisioning; not needed |
| tina_multimedia_demo (all) | demo apps |
| MtpDaemon, swupdate, ota-burnboot | OTA/MTP; not needed |
| benchmarks | not needed |
| libsec_key, libAWIspApi | no ISP/camera on Zero28 |

### Disabled — WiFi kernel modules

| Package | Reason |
|---------|--------|
| `kmod-net-xr829`, `kmod-net-xr829-40M` | Tina OpenWrt package for xr829; the kernel driver is compiled directly via CONFIG_XR829_WLAN=m/XRADIO=m — this Tina package is redundant |
| `xr829-firmware`, `xr829-rftest` | same |
| `kmod-net-rtl8188eu` | USB dongle driver, not built by kernel |
| all other kmod-net-* | wrong chip |

### Disabled — Bluetooth

| Package | Reason |
|---------|--------|
| bluez-alsa, bluez-daemon, bluez-utils, bluez-utils-extra | not needed |
| bcrm_patchram_plus | Broadcom BT; wrong chip |
| bluez-libs, libical, sbc | BT libs; not needed |

### Disabled — Networking / system

| Package | Reason |
|---------|--------|
| hostapd | AP mode not used |
| iperf, uclient-fetch | not needed |
| opkg | package manager; not needed at runtime |
| usign, uci, mtd, logd, dnsmasq | OpenWrt system utils not needed by NextUI |
| ntfs-3g, ntfsprogs-ntfs-3g | FAT32 is sufficient |
| iw | wifi CLI tool; wpa-cli covers what's needed |
| iptables | no firewall needed |

### Disabled — Libraries

| Package | Reason |
|---------|--------|
| libnss, nspr | NSS/NSPR pulled in by Allwinner default config; not needed |
| libinput, mtdev | input layer libs; SDL2 reads evdev directly |
| libsndfile, liboil | audio libs not used by NextUI |
| uclibcxx | uClibc C++; using glibc |
| libuclient, libsocket_db | OpenWrt networking libs; not needed |
| libgcrypt, libgpg-error, libexpat, libdbus, libconfig | not needed |
| libffi, libxml2 | not needed |
| libvpx, libtheora, libvorbis, libogg, libv4l | video/audio codecs not used |
| gnome (all) | not needed |

### Disabled — Utilities

| Package | Reason |
|---------|--------|
| getevent, dbus, dbus-utils | not needed |
| fontconfig | font rendering not needed at OS level |
| iozone3, memtester, stress | benchmarks |
| fbtest | framebuffer test tool |
| cpu_monitor | not needed |

### Disabled — Kernel modules

| Package | Reason |
|---------|--------|
| kmod-sunxi-vin | camera/video input; no camera on Zero28 |
| Cryptographic API modules (all) | not needed |
| kmod-lib-crc16 | not needed |

### Disabled — Firmware

| Package | Reason |
|---------|--------|
| aw869b-firmware | wrong chip |

### Disabled — Development

| Package | Reason |
|---------|--------|
| gdb | not needed in production image |
