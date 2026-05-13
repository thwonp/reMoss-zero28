#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Apply rotation patches (idempotent: -N skips already-applied hunks; || true ignores the
# non-zero exit patch returns when skipping)
cd /root/lichee/lichee/linux-4.9
patch -N -p1 < "$SCRIPT_DIR/patches/0001-feat-support-disp2-fb-hw-rotate.patch" || true
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

# Fix ffmpeg: remove Allwinner ISP camera deps (libAWIspApi disabled; not needed for playback)
FFMPEG_MK="/root/lichee/package/multimedia/ffmpeg/Makefile"
sed -i 's/ -lisp -lisp_ini -lAWIspApi//' "$FFMPEG_MK"
sed -i 's/ +libAWIspApi//' "$FFMPEG_MK"

# Fix netifd build failure under GCC 7 (-Werror=format-truncation on old snprintf code)
NETIFD_MK="/root/lichee/package/network/config/netifd/Makefile"
grep -q "Wno-error=format-truncation" "$NETIFD_MK" || \
    sed -i '/^CMAKE_OPTIONS/i TARGET_CFLAGS += -Wno-error=format-truncation\n' "$NETIFD_MK"

# Remove broken thirdparty IoT package Makefiles that cause OpenWrt scanner errors
rm -rf /root/lichee/package/thirdparty/duilite-lib \
       /root/lichee/package/thirdparty/midea-duilite-lib \
       /root/lichee/package/thirdparty/midea-mspeech-lib \
       /root/lichee/package/thirdparty/midea-player-lib \
       /root/lichee/package/thirdparty/uvoice-lib

# board.dts: enable 90° HW rotation for portrait 480×640 panel → logical landscape 640×480
DTS="/root/lichee/device/config/chips/a133/configs/aw3/board.dts"
sed -i 's/fb0_width\s*=\s*<480>/fb0_width               = <640>/' "$DTS"
sed -i 's/fb0_height\s*=\s*<640>/fb0_height              = <480>/' "$DTS"
grep -q "disp_rotation_used" "$DTS" || \
    sed -i '/fb0_height\s*=\s*<480>/a \\t\t\tdisp_rotation_used       = <1>;\n\t\t\tdegree0                  = <1>;\n\t\t\tfb0_buffer_num           = <2>;' "$DTS"

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
