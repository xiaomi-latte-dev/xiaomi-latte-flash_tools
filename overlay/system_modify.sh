#!/system/bin/sh
set -e

if [ -L "init.real" ];then
    # ProjectSakura 5.2 使用rusty-magisk，替换为SukiSU-Ultra
    # Remove rusty-magisk
    mv -f init.real init
    rm -rf system/bin/su
    rm -rf system/xbin/su
fi

# 部分系统缺失 libwvhidl.so
if ! find system/vendor -name "libwvhidl.so" 2>/dev/null; then
    echo "libwvhidl.so 未找到，移除 android.hardware.drm@1.3-service.widevine.rc"
    rm -rf system/vendor/etc/init/android.hardware.drm@1.3-service.widevine.rc
elif [ -f system/vendor/lib64/libwvhidl.so ] && file system/vendor/lib64/libwvhidl.so | grep -q "32-bit LSB" 2>/dev/null; then
    # ProjectSakura
    echo "vendor/lib64/libwvhidl.so 为32位，移动到vendor/lib"
    mv -f system/vendor/lib64/libwvhidl.so system/vendor/lib
fi

BUILD_PROP="system/vendor/build.prop"
MARKER_START="# start modify"
MARKER_END="# end modify"

echo "Config build.prop ..."
sed -i 's/ro.com.android.dateformat=MM-dd-yyyy/ro.com.android.dateformat=yyyy-MM-dd/g' $BUILD_PROP

if ! grep -qF "$MARKER_START" "$BUILD_PROP"; then
cat << EOF >> $BUILD_PROP
$MARKER_START
# 设置时区为上海
persist.sys.timezone=Asia/Shanghai
# 设置语言为中文（简体）
persist.sys.language=zh
persist.sys.country=CN
# 可选：同时设置 ro.product.locale（推荐用于 Android 6.0+）
ro.product.locale=zh-CN
# 设置DPI
ro.sf.lcd_density=320
# 默认开启无线ADB
service.adb.tcp.port=5555
# 不要在这里写 sys.usb.configfs。build.prop 只接受 ro.* / persist.* 前缀，
# sys.* 会被属性系统忽略（Android 11+），写进来也读不到，反而让人以为已配置。
# 该值改由 usb_udc_setup.sh 在 ffs 挂载完成后用 setprop 设置。
$MARKER_END
EOF
fi
echo "Config build.prop done."

echo "Config fstab ..."
# [ -f "fstab.android_x86_64" ] && ROOT_FSTAB="fstab.android_x86_64"
# [ -f "fstab.bliss_x86_64" ] && ROOT_FSTAB="fstab.bliss_x86_64"
# [ -f "fstab.lineage_x86_64_tablet" ] && ROOT_FSTAB="fstab.lineage_x86_64_tablet"
ROOT_FSTAB=`ls fstab.*`
[ -n "$ROOT_FSTAB" ] && sed -i '/mmc/d' "$ROOT_FSTAB"
# VENDOR_FSTAB="system/vendor/etc/fstab.internal.x86"
# [ -f "$VENDOR_FSTAB" ] && sed -i '/mmc/d' "$VENDOR_FSTAB"
echo "Config fstab done."

echo "Config usb configfs ..."
# MTP 的 gadget function 名对不上。
#
# Android 的 MTP 和 adb 一样走用户态 FunctionFS，内核没有 f_mtp.c。configfs
# 只接受 "ffs.<instance>" 形式的目录名，所以 MTP 的 function 实际是 ffs.mtp；
# 但 init.usb.configfs.rc 里 symlink 的源路径写死为 functions/mtp.gs0，
# 系统里也没有任何组件去创建它，结果是：
#   - symlink 静默失败，configs/b.1/f1 不存在
#   - UDC 照样被写入，sys.usb.state 显示 "mtp"，看起来正常
#   - 实际上 MTP 完全没有功能，mtpd 也不会起来
# configfs 不允许在 functions/ 下建软链接（Operation not permitted），
# 所以只能把 rc 里的路径改成实际存在的 ffs.mtp。
USB_CONFIGFS_RC="system/etc/init/hw/init.usb.configfs.rc"
if [ -f "$USB_CONFIGFS_RC" ]; then
    sed -i 's|functions/mtp\.gs0|functions/ffs.mtp|g' "$USB_CONFIGFS_RC"
    echo "  已把 mtp.gs0 改为 ffs.mtp: $(grep -c 'functions/ffs\.mtp' "$USB_CONFIGFS_RC") 处"
fi
echo "Config usb configfs done."

# 删除虚拟相机
VIRT_CAM="system/vendor/bin/hw/android.hardware.camera.provider@2.4-service-google"
if [ -f "$VIRT_CAM" ];then
    rm -rf "system/vendor/etc/init/android.hardware.camera.provider@2.4-service-google.rc"
    rm -rf "$VIRT_CAM"
fi

# 删除不必要的应用
echo "Removing unnecessary apps..."
# BlissOS
rm -rf "system/app/AboutBliss"
rm -rf "system/priv-app/BlissUpdater"
rm -rf "system/etc/permissions/privapp_whitelist_com.blissos.updater.xml"
# 屏幕旋转
rm -rf "system/app/com.googlecode.eyesfree.setorientation_1.1.4-10"
# 计算器
rm -rf "system/product/app/yetCalc"
# 信息
rm -rf "system/product/app/messaging"
# 联系人
rm -rf "system/product/priv-app/Contacts"
rm -rf "system/product/etc/permissions/com.android.contacts.xml"
# 拨号
rm -rf "system/product/priv-app/Dialer"
rm -rf "system/product/etc/permissions/com.android.dialer.xml"
# 触摸屏校准 ProjectSakura 附带
rm -rf "system/priv-app/TSCalibration2"
# 桌面启动器
rm -rf "system/priv-app/com.farmerbb.taskbar" # ProjectSakura
rm -rf "system/etc/permissions/privapp-permissions-com.farmerbb.taskbar.xml"
rm -rf "system/system_ext/priv-app/com.farmerbb.taskbar"
rm -rf "system/system_ext/etc/permissions/privapp-permissions-com.farmerbb.taskbar.xml"
rm -rf "system/priv-app/com.farmerbb.taskbar.support" # ProjectSakura
rm -rf "system/etc/permissions/privapp-permissions-com.farmerbb.taskbar.support.xml"
rm -rf "system/system_ext/priv-app/com.farmerbb.taskbar.support"
rm -rf "system/system_ext/etc/permissions/privapp-permissions-com.farmerbb.taskbar.support.xml"
rm -rf "system/system_ext/priv-app/smart-dock"
rm -rf "system/system_ext/etc/permissions/cu.axel.smartdock-permissions.xml"
# FOSS
rm -rf "system/app/at.bitfire.davdroid"
rm -rf "system/app/eu.faircode.email"
rm -rf "system/app/com.reecedunn.espeak"
rm -rf "system/app/Phonograph"
echo "Removing unnecessary apps done."

# 删除不必要的固件
echo "Removing unnecessary firmware..."
rm -rf "system/vendor/firmware/amd"*
rm -rf "system/vendor/firmware/radeon"
rm -rf "system/vendor/firmware/amlogic"
rm -rf "system/vendor/firmware/arm"
rm -rf "system/vendor/firmware/nvidia"
rm -rf "system/vendor/firmware/qcom"
rm -rf "system/vendor/firmware/iwlwifi-"*
echo "Removing unnecessary firmware done."
