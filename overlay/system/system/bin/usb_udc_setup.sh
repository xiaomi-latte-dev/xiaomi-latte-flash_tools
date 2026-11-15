#!/system/bin/sh
# UDC 前置：创建 USB gadget 骨架、挂载 FunctionFS，并开启 configfs 模式。
#
# Android 的 init.usb.configfs.rc 只做 write/symlink，假设 gadget 已经存在；
# 而 build.prop 里的 sys.usb.configfs=1 因为 sys.* 前缀不被属性系统接受
# （Android 11+ 只认 ro.*/persist.*），运行时读出来是 0。
#
# 那个 0 会让 init.usb.configfs.rc 的所有触发器失效，改由 init.usb.rc 的
# legacy 分支在 ~10.3s 抢先拉起 adbd；此时 FunctionFS 还没挂好，adbd 打不开
# ep0，会静默跳过整个 USB 初始化。
#
# 所以这里做两件事：铺好 gadget + ffs，然后把 configfs 置 1 让系统接管
# 后续的 sys.usb.config 触发链（我们不直接启动 adbd）。

UDC=$(ls /sys/class/udc/ 2>/dev/null | head -n 1)
[ -n "$UDC" ] || exit 0

# configfs 可能还没挂上，等一会儿
i=0
while [ ! -d /config/usb_gadget ] && [ $i -lt 100 ]; do
    sleep 0.1
    i=$((i+1))
done
[ -d /config/usb_gadget ] || exit 1

DMI=/sys/class/dmi/id
dmi() { cat "$DMI/$1" 2>/dev/null; }

# 标识全部取自 DMI，避免写死机器专属的值。
PRODUCT=$(dmi product_name)
VENDOR=$(dmi sys_vendor)
SERIAL=$(dmi product_serial)

# 读不到就退回通用值，保证 gadget 仍能创建。
[ -n "$PRODUCT" ] || PRODUCT="Android"
[ -n "$VENDOR" ] || VENDOR="Android"
# 序列号必须有值；product_uuid 是可靠的后备。
[ -n "$SERIAL" ] || SERIAL=$(dmi product_uuid)
[ -n "$SERIAL" ] || SERIAL="0123456789ABCDEF"

cd /config/usb_gadget/ || exit 1
mkdir -p g1 && cd g1 || exit 1

echo 0x18d1 > idVendor
# 0x4ee2 = MTP + ADB，这是 libmtp / KDE Solid 都认识的标准组合 ID。
# 不要用 AOSP 参考值 0x4ee7：它在 libmtp 1.1.23 的设备库里是 UNKNOWN，
# 主机会报 "文件或文件夹 udi=... 不存在"，MTP 打不开。
# 常见组合（Google VID 0x18d1）：
#   0x4ee1 MTP only   0x4ee2 MTP + ADB
#   0x4ee5 PTP + ADB  0x4ee7 AOSP 参考值（libmtp 不认）
echo 0x4ee2 > idProduct
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

mkdir -p strings/0x409
echo "$SERIAL" > strings/0x409/serialnumber
echo "$VENDOR" > strings/0x409/manufacturer
echo "$PRODUCT" > strings/0x409/product

mkdir -p configs/b.1/strings/0x409
echo adb > configs/b.1/strings/0x409/configuration
echo 500 > configs/b.1/MaxPower

# 关键顺序：先建 ffs.adb 才会注册 functionfs 文件系统（f_fs.c 的惰性注册），
# 之后 mount 才能成功，顺序反了会得到 "No such device"。
mkdir -p functions/ffs.adb

# MTP 同样走用户态 FunctionFS，内核没有独立的 f_mtp.c。
# configfs 只接受 "ffs.<instance>" 形式的目录名，所以这里建 ffs.mtp。
# init.usb.configfs.rc 里原本指向 functions/mtp.gs0，那个名字在 configfs 下
# 根本创建不出来；system_modify.sh 已用 sed 把 rc 里的路径改成 ffs.mtp。
mkdir -p functions/ffs.mtp

# 关键：父目录 /dev/usb-ffs 必须可进入。
# adbd 在 main.cpp 里先 drop_privileges() 再 access("/dev/usb-ffs/adb/ep0")，
# 而 mkdir 出来的 /dev/usb-ffs 是 0700 root:root，降权成 shell(2000) 的 adbd
# 连这个目录都进不去，access() 直接失败，于是静默跳过整个 USB 初始化 ——
# 日志里看不到任何 USB 相关内容，只有 main.cpp:296 Event loop starting。
# 光给挂载点设 uid/gid 不够，父目录的 x 位同样必须放开。
mkdir -p /dev/usb-ffs/adb
chown 2000:1000 /dev/usb-ffs
chmod 0755 /dev/usb-ffs
# 挂载点本身用 0500（f_fs 的默认 root_mode）+ 归属 shell:system，
# 与 AOSP init.rc 的 "mount functionfs ... uid=2000,gid=1000" 一致。
mount -t functionfs adb /dev/usb-ffs/adb -o uid=2000,gid=1000 2>/dev/null

# MTP 的 FunctionFS 挂载点。libmtp.so 里写死的路径是
# /dev/usb-ffs/mtp/ep0..ep3，不挂这里 MTP 完全无法工作。
#
# 属主必须是 system(1000)，不是 shell(2000)：
# ep0 由 system_server 通过 UsbDeviceManager 的 nativeOpenControl() 打开
# （com_android_server_UsbDeviceManager.cpp 里 open(FFS_MTP_EP0, O_RDWR)），
# 而 system_server 以 uid 1000 运行。若挂成 shell，open 会 EACCES，
# 该函数返回 NULL，于是 UsbDeviceManager.mControlFds 里存的是 null，
# MtpService 就会报 "Couldn't get control FD!" / "Failed to start usb driver!"，
# 连带 ffs.mtp 的 ep0 无人持有，UDC 绑定失败（-ENODEV），整个 USB 都起不来。
#
# 另外必须放开 fmode：f_fs 的默认端点是 0600 且属主只有一个人，
# 但 MTP 的 ep0 有**两个**不同 uid 的消费者：
#   - system_server (uid 1000)：UsbDeviceManager 的 nativeOpenControl()
#   - android.process.media (uid 10xxx)：MtpService / MtpServer 实际所在进程
# 只设 uid= 的话另一个必然 EACCES，表现就是 MtpServer 报
# "Failed to start usb driver!"，而 openEndpoints 的 PLOG 一条都打不出来。
# 所以用 fmode=0666 让两者都能打开，实际隔离交给 SELinux。
# （内核 f_fs.c 里 ctx->perms.mode 默认就是 S_IFREG|0600，必须显式覆盖）
mkdir -p /dev/usb-ffs/mtp
# 注意：f_fs 只认 rmode/fmode/mode/uid/gid，没有 dmode！
# 写了 dmode 会整个挂载失败并返回 EINVAL（Invalid argument），
# 而脚本里用 2>/dev/null 吞掉错误，表现为 /dev/usb-ffs/mtp 是空目录、
# MtpService 报 "Couldn't get control FD!"，非常难查。
mount -t functionfs mtp /dev/usb-ffs/mtp -o uid=1000,gid=1000,fmode=0666,rmode=0755

# 现在 ffs 已就绪，切到 configfs 模式让系统的属性触发链接管：
# init.usb.configfs.rc 会在 sys.usb.ffs.ready=1 时绑定 UDC，
# 而 adbd 由 "on property:sys.usb.config=adb && sys.usb.configfs=1" 启动。
setprop sys.usb.configfs 1

exit 0