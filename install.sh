#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Apply rotation patches (idempotent: -N skips already-applied hunks; || true ignores the
# non-zero exit patch returns when skipping)
cd /root/lichee/lichee/linux-4.9
patch -N -p1 < "$SCRIPT_DIR/patches/0001-feat-support-disp2-fb-hw-rotate.patch" || true
python3 -c "
fname = '/root/lichee/lichee/linux-4.9/drivers/video/fbdev/sunxi/disp2/disp/fb_g2d_rot.c'
sig = 'int fb_get_rot_degree(unsigned int fb_id)'
with open(fname) as f: lines = f.readlines()
indices = [i for i, l in enumerate(lines) if sig in l]
if len(indices) <= 1: exit(0)
second = indices[1]
depth = 0; end = second
for i in range(second, len(lines)):
    depth += lines[i].count('{') - lines[i].count('}')
    if i > second and depth == 0: end = i; break
start = second
while start > 0 and lines[start - 1].strip() == '': start -= 1
del lines[start:end + 1]
with open(fname, 'w') as f: f.writelines(lines)
"
# Zero28 90/270 rotation fixes (applied as sed/python — 0002 patch context mismatches BSP output)
FB_G2D="/root/lichee/lichee/linux-4.9/drivers/video/fbdev/sunxi/disp2/disp/fb_g2d_rot.c"
DEV_FB="/root/lichee/lichee/linux-4.9/drivers/video/fbdev/sunxi/disp2/disp/dev_fb.c"
sed -i '72s/dst_image_h\.width;/dst_image_h.height;/' "$FB_G2D"
sed -i '74s/dst_image_h\.height;/dst_image_h.width;/' "$FB_G2D"
sed -i 's/FB_ROTATION_HW_0 && degree > FB_ROTATION_HW_270/FB_ROTATION_HW_0 || degree > FB_ROTATION_HW_270/' "$FB_G2D"
python3 -c "
fname = '$DEV_FB'
with open(fname) as f: c = f.read()
if 'degree_int == 1 || degree_int == 3' in c: exit(0)
block = '#if defined(CONFIG_SUNXI_DISP2_FB_HW_ROTATION_SUPPORT)\n\tif (degree_int == 1 || degree_int == 3) {\n\t\tint tmp = dst_width;\n\t\tdst_width = dst_height;\n\t\tdst_height = tmp;\n\t}\n#endif\n\n'
target = '\tif (degree_int == 2) { /* copy with rotate 180 */'
with open(fname, 'w') as f: f.write(c.replace(target, block + target, 1))
"

cd /root/lichee/lichee/brandy-2.0/u-boot-2018
patch -N -p1 < "$SCRIPT_DIR/patches/0001-feat-support-fb-bootlogo-rotate.patch" || true

cd "$SCRIPT_DIR"

# Patch board defconfig for Phase II toolchain (GCC 7.4.1, binutils 2.28, glibc 2.29).
# The Tina build system copies target/allwinner/a133-aw3/defconfig over .config at the
# start of every make invocation (toplevel.mk .config rule, Tina elif branch). Because
# this copy happens inside a recursive sub-make spawned after prepare-tmpinfo refreshes
# out/host/.prereq-build, it can fire after set-config.sh has already run, wiping those
# changes. Fixing the board defconfig itself is the only reliable solution.
DEFCONFIG="/root/lichee/target/allwinner/a133-aw3/defconfig"
if ! grep -q 'CONFIG_GCC_USE_VERSION_7_4_LINARO=y' "$DEFCONFIG"; then
    sed -i \
        -e 's/CONFIG_GCC_VERSION_6_4_LINARO=y/# CONFIG_GCC_VERSION_6_4_LINARO is not set/' \
        -e 's/CONFIG_GCC_VERSION="linaro-6.4-2017.11"/CONFIG_GCC_VERSION="linaro-7.4-2019.02"/' \
        -e 's/CONFIG_BINUTILS_VERSION_2_27=y/# CONFIG_BINUTILS_VERSION_2_27 is not set/' \
        -e 's/CONFIG_BINUTILS_VERSION="2.27"/CONFIG_BINUTILS_VERSION="2.28"/' \
        -e 's/CONFIG_GLIBC_VERSION_2_11=y/# CONFIG_GLIBC_VERSION_2_11 is not set/' \
        -e 's/CONFIG_GLIBC_VERSION_2_21=y/# CONFIG_GLIBC_VERSION_2_21 is not set/' \
        -e 's/CONFIG_GLIBC_VERSION_2_22=y/# CONFIG_GLIBC_VERSION_2_22 is not set/' \
        -e 's/CONFIG_GLIBC_VERSION_2_23=y/# CONFIG_GLIBC_VERSION_2_23 is not set/' \
        -e 's/CONFIG_GLIBC_VERSION="2.11"/CONFIG_GLIBC_VERSION="2.29"/' \
        -e 's/CONFIG_LIBC_VERSION="2.11"/CONFIG_LIBC_VERSION="2.29"/' \
        -e 's/# CONFIG_UPDATE_TOOLCHAIN is not set/CONFIG_UPDATE_TOOLCHAIN=y/' \
        "$DEFCONFIG"
    cat >> "$DEFCONFIG" << 'EOF'
CONFIG_TOOLCHAINOPTS=y
CONFIG_NEED_TOOLCHAIN=y
# CONFIG_GCC_USE_VERSION_6_4_LINARO is not set
CONFIG_GCC_USE_VERSION_7_4_LINARO=y
# CONFIG_BINUTILS_USE_VERSION_2_27 is not set
CONFIG_BINUTILS_USE_VERSION_2_28=y
# CONFIG_GLIBC_USE_VERSION_2_11 is not set
# CONFIG_GLIBC_USE_VERSION_2_21 is not set
# CONFIG_GLIBC_USE_VERSION_2_22 is not set
# CONFIG_GLIBC_USE_VERSION_2_23 is not set
CONFIG_GLIBC_USE_VERSION_2_29=y
CONFIG_LIBC_USE_GLIBC=y
EOF
    echo "Patched board defconfig: Phase II toolchain (GCC 7.4.1, binutils 2.28, glibc 2.29)"
fi

# Fix fontconfig 2.12.1: FC_OBJECT(CHAR_WIDTH,...,NULL) generates PRI_CHAR_WIDTH_STRONG/WEAK via the
# dummy enum but they are absent from the real FcMatcherPriority enum; GCC 7 rejects the reference
# in the static struct initializer. Patch adds PRI1(CHAR_WIDTH) to the real enum.
python3 -c "
import os
d = '/root/lichee/package/utils/fontconfig/patches'
p = os.path.join(d, '001-fix-char-width-priority-gcc7.patch')
if os.path.exists(p): exit(0)
os.makedirs(d, exist_ok=True)
with open(p, 'w') as f:
    f.write('--- a/src/fcmatch.c\n+++ b/src/fcmatch.c\n@@ -300,6 +300,7 @@ typedef enum _FcMatcherPriority {\n     PRI1(SLANT),\n     PRI1(WEIGHT),\n     PRI1(WIDTH),\n+    PRI1(CHAR_WIDTH),\n     PRI1(DECORATIVE),\n     PRI1(ANTIALIAS),\n     PRI1(RASTERIZER),\n')
"
rm -rf /root/lichee/out/a133-aw3/compile_dir/target/fontconfig-2.12.1

# Remove packages that fail to build under glibc 2.29 and are not needed on Zero28
rm -rf /root/lichee/package/allwinner/camerademo                        # libisp.so references major()/minor() absent from glibc 2.29
rm -rf /root/lichee/package/allwinner/resample                          # libc.so missing dependency; libsamplerate covers this
rm -rf /root/lichee/package/allwinner/tina_multimedia_demo/trecorderdemo  # links awrecorder→libisp.so, same major()/minor() failure

# Fix ffmpeg: remove Allwinner ISP camera deps (libAWIspApi disabled; not needed for playback)
FFMPEG_MK="/root/lichee/package/multimedia/ffmpeg/Makefile"
sed -i 's/ -lisp -lisp_ini -lAWIspApi//' "$FFMPEG_MK"
sed -i 's/ +libAWIspApi//' "$FFMPEG_MK"
grep -q "disable-indevs" "$FFMPEG_MK" || \
    sed -i 's/--disable-outdevs/--disable-outdevs \\\n\t--disable-indevs/' "$FFMPEG_MK"

# Fix netifd build failure under GCC 7 (-Werror=format-truncation on old snprintf code)
NETIFD_MK="/root/lichee/package/network/config/netifd/Makefile"
grep -q "Wno-error=format-truncation" "$NETIFD_MK" || \
    sed -i '/^CMAKE_OPTIONS/i TARGET_CFLAGS += -Wno-error=format-truncation\n' "$NETIFD_MK"

# Fix libcedarx/libcedarc build failure under GCC 7 (-Werror=format-truncation in vencoderDemo).
# Two patches needed: configure-time CFLAGS and make-time CFLAGS.  The Build/Compile rule
# passes its own CFLAGS= to $(MAKE) which overrides whatever configure baked into the
# generated Makefile, so both lines must carry the flag.
CEDAR_MK="/root/lichee/package/allwinner/tina_multimedia/Makefile"
grep -q 'ENABLE_ZLIB__.*Wno-error=format-truncation' "$CEDAR_MK" || \
    sed -i 's/CFLAGS="-D__ENABLE_ZLIB__ -D\$(VE_OFFSET)/CFLAGS="-D__ENABLE_ZLIB__ -Wno-error=format-truncation -D$(VE_OFFSET)/' "$CEDAR_MK"
grep -q 'TARGET_CFLAGS.*Wno-error=format-truncation' "$CEDAR_MK" || \
    sed -i 's/CFLAGS="\$(TARGET_CFLAGS) -D__ENABLE_ZLIB__ -D\$(VE_OFFSET)/CFLAGS="$(TARGET_CFLAGS) -Wno-error=format-truncation -D__ENABLE_ZLIB__ -D$(VE_OFFSET)/' "$CEDAR_MK"
# libcedarx: fix -Werror=nonnull in CdxRtspStream.cpp (GCC 7 null-arg-to-memcpy check)
# Flag must be in CPPFLAGS because libcedarx is compiled as C++ (CXX) not C
grep -q 'TARGET_CPPFLAGS.*Wno-error=nonnull' "$CEDAR_MK" || \
    sed -i 's/CPPFLAGS="\$(TARGET_CPPFLAGS) -D__ENABLE_ZLIB__  -D\$(TINA_CHIP_TYPE)/CPPFLAGS="$(TARGET_CPPFLAGS) -Wno-error=nonnull -D__ENABLE_ZLIB__  -D$(TINA_CHIP_TYPE)/' "$CEDAR_MK"
# libcedarx: fix -Werror=format-truncation in CdxMp4MuxerLib.c (GCC 7 snprintf truncation check)
# Covers both libcedarx full and audio-only make targets (both use TINA_CHIP_TYPE in CFLAGS)
grep -q 'TINA_CHIP_TYPE.*Wno-error=format-truncation\|Wno-error=format-truncation.*TINA_CHIP_TYPE' "$CEDAR_MK" || \
    sed -i 's/CFLAGS="\$(TARGET_CFLAGS) -D__ENABLE_ZLIB__ -D\$(TINA_CHIP_TYPE)/CFLAGS="$(TARGET_CFLAGS) -Wno-error=format-truncation -D__ENABLE_ZLIB__ -D$(TINA_CHIP_TYPE)/g' "$CEDAR_MK"

# Fix e2fsprogs build failure under glibc 2.29 (makedev/major removed from sys/types.h)
E2FS_MK="/root/lichee/package/utils/e2fsprogs/Makefile"
grep -q "sysmacros" "$E2FS_MK" || \
    sed -i 's/-fdata-sections$/-fdata-sections -include sys\/sysmacros.h/' "$E2FS_MK"

# Fix xr829: SUPPORT_EPTA defined unconditionally but epta_stat_dbg_ctrl is
# only in debug.o (compiled only with CONFIG_XRADIO_DEBUG); tie them together
XR829_MK="/root/lichee/lichee/linux-4.9/drivers/net/wireless/xr829/wlan/Makefile"
grep -q 'CONFIG_XRADIO_DEBUG.*SUPPORT_EPTA' "$XR829_MK" || \
    sed -i 's/^ccflags-y += -DSUPPORT_EPTA$/ccflags-$(CONFIG_XRADIO_DEBUG) += -DSUPPORT_EPTA/' "$XR829_MK"

# Remove broken thirdparty IoT package Makefiles that cause OpenWrt scanner errors
rm -rf /root/lichee/package/thirdparty/duilite-lib \
       /root/lichee/package/thirdparty/midea-duilite-lib \
       /root/lichee/package/thirdparty/midea-mspeech-lib \
       /root/lichee/package/thirdparty/midea-player-lib \
       /root/lichee/package/thirdparty/uvoice-lib

# Increase boot-resource partition: 640×480 logo is ~1886 sectors; stock size is 512
PART_FEX="/root/lichee/device/config/chips/a133/configs/aw3/linux/sys_partition.fex"
sed -i '/name.*=.*bootloader/{n;s/size\s*=\s*512/size         = 2048/}' "$PART_FEX"

# board.dts: enable 90° HW rotation for portrait 480×640 panel → logical landscape 640×480
DTS="/root/lichee/device/config/chips/a133/configs/aw3/board.dts"
sed -i 's/fb0_width\s*=\s*<480>/fb0_width               = <640>/' "$DTS"
sed -i 's/fb0_height\s*=\s*<640>/fb0_height              = <480>/' "$DTS"
grep -q "degree0" "$DTS" || \
    sed -i '/fb0_height\s*=\s*<480>/a \\t\t\tdisp_rotation_used       = <1>;\n\t\t\tdegree0                  = <3>;' "$DTS"

# Kernel defconfig additions (idempotent guards)
DEF="/root/lichee/lichee/linux-4.9/arch/arm64/configs/sun50iw10p1smp_defconfig"
grep -q "SUNXI_DISP2_FB_HW_ROTATION_SUPPORT" "$DEF" || echo "CONFIG_SUNXI_DISP2_FB_HW_ROTATION_SUPPORT=y"  >> "$DEF"
grep -q "CONFIG_NLS_ISO8859_1"               "$DEF" || echo "CONFIG_NLS_ISO8859_1=y"                        >> "$DEF"
grep -q "CONFIG_NLS_UTF8"                    "$DEF" || echo "CONFIG_NLS_UTF8=y"                             >> "$DEF"
grep -q "CONFIG_FAT_DEFAULT_IOCHARSET"       "$DEF" || echo 'CONFIG_FAT_DEFAULT_IOCHARSET="utf8"'           >> "$DEF"
grep -q "CONFIG_VIDEO_SUNXI_VIN"             "$DEF" || echo "# CONFIG_VIDEO_SUNXI_VIN is not set"           >> "$DEF"

cp bootlogo.bmp /root/lichee/target/allwinner/generic/boot-resource/boot-resource/

cp etc/rc.local /root/lichee/target/allwinner/a133-aw3/base-files/etc/
cp etc/banner /root/lichee/package/base-files/files/etc/

cp -r usr /root/lichee/package/add-rootfs-demo/
gzip -c /root/lichee/.config > /root/lichee/package/add-rootfs-demo/usr/magicx/tina_config.gz

echo "after building run add-rootfs-demo"
