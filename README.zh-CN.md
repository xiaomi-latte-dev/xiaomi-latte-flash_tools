# xiaomi-latte-flash_tools

[English](README.md) | [简体中文](README.zh-CN.md)

面向**小米平板 2**（`latte`，Intel Cherry Trail / x86_64 平板）的
**Android-x86** 自定义镜像构建与刷机工具链。

它会读取一份基于 Android-x86 的官方 ISO（BlissOS、LineageOS、ProjectSakura 等）、
一份预编译的 `zenith` 内核，以及一组设备专用 overlay，
最终产出一套可用 fastboot 刷入的分区镜像（`gpt.bin`、`boot.img`、`system.img`、`data.img`）。

## 特性

- **经 SHIM/GRUB 的替代引导路径** —— 把 Fedora `shim` + `grub2-efi` 打包进 `boot.img`，
  绕过原厂 `fastboot.efi` 加载器。原厂固件只能启动原厂 Android-IA 镜像，
  而 GRUB 可启动 Linux、Windows、Android-x86 等任意 UEFI 操作系统。
- **多发行版支持** —— 通过一个 `VER=` 开关即可选择源 ISO、对应的 initrd 补丁
  以及 system 镜像压缩方式（见[版本对照表](#版本对照表)）。
- **设备 overlay** —— 修改过的 ACPI DSDT、电容按键重映射、Broadcom BCM4356
  无线/蓝牙固件、RT5659 编解码器的 ALSA UCM，以及默认语言/时区/DPI 配置。
- **USB 网络 + SSH** —— ECM/RNDIS gadget 内置 `dnsmasq` DHCP 服务，
  并运行 `dropbear` SSH 服务，可通过 `192.168.255.1` 访问。
- **镜像格式灵活** —— `system.img` 支持 `erofs` 或 `squashfs`（自动选择），
  `data.img` 支持 `f2fs` 或 `ext4`，另外可选生成稀疏镜像 `data.simg`。
- **主机侧调试** —— 可用 QEMU/KVM 运行构建产物，或挂载镜像进行检查。
- **一键刷机（Windows）** —— `DNX_flash_*.bat` 脚本，并带机型校验。

## 前置条件

- 构建需要 Linux 主机（loop 挂载需要 root/`sudo`）；仅刷机可用 Windows。
- 平板上需能启动随附的 UEFI fastboot。该设备没有 Android Bootloader；
  `fastboot.efi` 即用于刷机的 UEFI fastboot，其角色由 Android-IA 的安全启动链承担。
- makefile 会用到的宿主依赖包：

  ```bash
  # 以下为 Debian/Ubuntu 包名（其他发行版请自行对应）
  sudo apt install wget p7zip-full squashfs-tools f2fs-tools erofs-utils \
       gcc acpica-tools rpm cpio patch libguestfs-tools
  ```

  可选依赖：
  - `qemu-system-x86`、`qemu-utils`、`ovmf` —— `qemu` / `qemu-iso` 目标需要。
  - `android-sdk-libsparse-utils`（`img2simg`）—— 用于生成稀疏镜像 `data.simg`。
  - `rpm2cpio`（来自 `rpm`）—— 解包 `shim` / `grub2-efi` RPM 时必需。

## 输入文件

把所需文件放到仓库根目录。makefile 通过通配符自动查找，因此文件名必须匹配：

| 文件 | 匹配模式 | 说明 |
| --- | --- | --- |
| 源 ISO | `*<VER>*-*.iso` | 例如 `VER=14` 对应 `Bliss-v14.10.3-x86_64-OFFICIAL-foss-20241012.iso` |
| 源 ISO（`VER=5`） | `ProjectSakura-5.*.iso` | makefile 中对该版本做了特殊处理 |
| 内核包 | `kernel-*-zenith.tar.gz` | 解包出 `lib/modules/<kernel>` |
| shim RPM | `shim-x64.rpm` | 缺失时自动下载 |
| grub2 RPM | `grub2-efi-x64.rpm` | 缺失时自动下载 |

下载示例：

- BlissOS：<https://sourceforge.net/projects/blissos-x86/files/>
- LineageOS for x86：<https://sourceforge.net/projects/lineageos-for-x86/files/>
- `zenith` 内核：<https://github.com/Qs315490/android-x86-kernel-latte/actions>

```bash
# BlissOS 14.10.3 示例（VER=14）
wget -O Bliss-v14.10.3-x86_64-OFFICIAL-foss-20241012.iso \
  "https://sourceforge.net/projects/blissos-x86/files/Official/BlissOS14/FOSS/Generic/Bliss-v14.10.3-x86_64-OFFICIAL-foss-20241012.iso/download"

# 内核包（zenith 系列）
wget -O kernel-6.12.30-zenith.tar.gz \
  "https://github.com/Qs315490/android-x86-kernel-latte/releases/download/..."
```

## 版本对照表

`VER` 默认为 `14`，取值必须是下表之一（来源于 makefile）：

| `VER` | Android-x86 发行版 | 内核 |
| --- | --- | --- |
| `17.1` | LineageOS 17.1（Android 10） | `5.8.0-android-x86_64` |
| `5` | ProjectSakura 5.2（Android 11） | `5.10.61-GoogleLTS-xanmod1-pledge` |
| `14` | BlissOS 14.10.x（Android 11） | `6.1.112-gloria-xanmod1` / `6.6.102-crimson-xanmod1` |
| `15` | BlissOS 15（Android 12） | `6.1.112-gloria-xanmod1` |
| `16` | BlissOS 16（Android 13） | `6.1.112-gloria-xanmod1` |
| `17.2` | BlissOS Zenith 17.2（Android 14） | `6.7.10-zenith-xanmod1` |
| `18` | BlissOS 18.4（Android 15） | `6.6.89-crimson-xanmod1` |
| `21` | LineageOS 21.1（Android 14） | `6.12.30-zenith` |

## 引导链路

原厂固件只能通过 `fastboot.efi` 启动它自己的 Android-IA 镜像。
本项目在 `boot.img` 中铺设了一条替代的 UEFI 引导路径：

1. **SHIM**（`shimx64.efi` / `bootx64.efi`）—— Fedora 签名的第一阶段
   加载器。在本方案中它由 EFI 启动项直接拉起，因此平板引导的是
   SHIM/GRUB 链路，**而不是** `fastboot.efi`。
2. **GRUB**（`grubx64.efi`）—— 渲染引导菜单并加载内核 + initrd。
   这是与原厂固件的关键差别：GRUB 可以引导 **任意 UEFI 操作系统**
   （Linux、Windows、Android-x86 等），而不仅仅是原厂 Android-IA 镜像。
3. **MOK**（`MOK.cer` / `MOK.crt` / `MOK.key`）—— Machine Owner Key。
   注册后可在 **保持 UEFI 安全启动开启** 的情况下正常引导；
   否则安全启动会拒绝未签名的 GRUB 与内核。
4. **setup_var.efi** —— 一个用于读写隐藏固件（BIOS）设置的 UEFI 小工具，
   这些设置仅以 EFI 变量形式暴露（例如 GRUB「电源」子菜单里的 OTG 开关）。


## 构建

```bash
# 使用默认 VER=14 构建全部镜像（gpt.bin、boot.img、system.img、data.img）
make

# 指定发行版
make all VER=21

# 打印完整命令行
make all VER=21 V=1
```

需要时可覆盖镜像大小：

```bash
make all VER=21 BOOT_SIZE=64 DATA_SIZE=4096
```

产物输出到 `images-<VER>/`（例如 `make VER=21` → `images-21/`）。

### 构建变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `VER` | `14` | 目标发行版，决定 ISO 选择、initrd 补丁与压缩方式 |
| `BOOT_SIZE` | `64` | `boot.img`（ESP/FAT32）大小，单位 MiB |
| `DATA_SIZE` | `2048` | `data.img` 大小，单位 MiB |
| `V` | `0` | 设为 `V=1` 时打印 makefile 执行的每条命令 |

### make 目标

| 目标 | 说明 |
| --- | --- |
| `all` | 构建 `gpt.bin`、`boot.img`、`system.img`、`data.img` |
| `gpt.bin` | 根据 `device_files/gpt.ini` 生成 GPT |
| `boot.img` | 构建 64 MiB 的 FAT32 ESP，内含 shim + GRUB + 内核 + initrd |
| `system.img` | 解包 ISO 中的 system 镜像，应用 overlay 后用 erofs/squashfs 重新打包 |
| `data.img` | 创建 `data` 分区（有 f2fs 则用 f2fs，否则 ext4）并生成稀疏镜像 `data.simg` |
| `unpack_iso` / `unpack_initrd` / `unpack_system` | 解包对应源文件 |
| `unpack_shim_grub` / `unpack_kenrel` | 解包 shim/grub RPM 与内核压缩包 |
| `patch_initrd` / `pack_initrd` | 给 initrd 打补丁，然后重新打包 |
| `pack_system` | 仅重新打包 system 镜像 |
| `mount_boot` / `umount_boot` | 挂载 / 卸载 `boot.img` |
| `mount_system` / `umount_system` | 挂载 / 卸载解包后的 system 镜像 |
| `mount_data` / `umount_data` | 挂载 / 卸载 `data.img` |
| `flash_all` | 用 fastboot 刷入 gpt + boot + system + data，然后重启 |
| `flash_gpt` / `flash_boot` / `flash_system` / `flash_data` | 刷入单个分区 |
| `flash_boot_system` | 刷入 boot 与 system |
| `flash_reboot` | 执行 `fastboot reboot` |
| `ssh` | 以 `root@192.168.255.1` SSH 登录已启动的设备/虚拟机 |
| `qemu` | 在 QEMU/KVM 中启动构建出的内核/initrd/system/data |
| `qemu-iso` | 在 QEMU/KVM 中启动源 ISO |
| `mount_qemu_data` / `umount_qemu_data` | 通过 `guestmount` 挂载 QEMU 磁盘镜像 |
| `dnx.7z` | 把所有镜像与 `.bat` 脚本打包为 `DNX_Fastboot.7z` |
| `clean` | 删除 `build/` 并卸载 loop 设备 |
| `clean_images` / `clean_images_all` | 删除单个 / 全部 `images-*` 目录 |
| `clean_all` | 相当于 `clean` + `clean_images_all`，并删除已下载的 RPM 与生成的 DSDT |
| `clean_iso` / `clean_initrd` / `clean_system` / `clean_data` / `clean_boot` / `clean_kenrel` / `clean_qemu` | 删除对应的构建产物 |

> 注意：`unpack_kenrel` 与 `clean_kenrel` 沿用 makefile 中的原始拼写。

## 刷机

### Linux（fastboot）

```bash
# 构建并刷入全部镜像，然后重启
make flash_all VER=21
```

或手动刷入：

```bash
fastboot boot  overlay/boot/EFI/BlissOS/fastboot.efi
fastboot oem unlock   # 由 fastboot.efi 处理，并非设备 Bootloader
fastboot flash oemvars device_files/oemvars.txt
fastboot flash oemvars device_files/oemvars-battery-config-fake-disabled.txt
fastboot flash oemvars device_files/oemvars-battery-config-fake.txt
fastboot flash gpt     images-21/gpt.bin
fastboot flash boot    images-21/boot.img
fastboot flash system  images-21/system.img
fastboot flash data    images-21/data.img   # 或 data.simg
fastboot reboot
```

`oemvars-battery-config-fake*.txt` 用于切换假电池标志：

- `oemvars-battery-config-fake.txt` → `BatteryConfig ro.boot.fake_battery=1`
- `oemvars-battery-config-fake-disabled.txt` → `BatteryConfig ro.boot.fake_battery=0`

请按你期望的电池上报方式选择刷入其中一个。

### Windows（一键刷机）

运行批处理脚本时需保证 `fastboot` 在 `PATH` 中。脚本要求其所在目录结构如下：

```
<刷机目录>/
├── DNX_flash_*.bat
├── fastboot.efi           # 由 overlay/boot/EFI/BlissOS/fastboot.efi 复制而来
├── device_files/          # oemvars*.txt
│   └── oemvars*.txt
└── images/                # 由 images-<VER>/ 复制或重命名而来
    ├── gpt.bin
    ├── boot.img
    ├── system.img
    └── data.img / data.simg
```

| 脚本 | 作用 |
| --- | --- |
| `DNX_flash_all.bat` | 校验机型、解锁，刷入 oemvars + gpt + boot + system + data，然后重启 |
| `DNX_flash-boot.bat` | 仅刷入 `boot.img` |
| `DNX_flash-system.bat` | 仅刷入 `system.img` |
| `DNX_flash-data.bat` | 仅刷入 `data.img`（优先使用 `data.simg`） |

`DNX_flash_all.bat` 会先启动 `fastboot.efi`，校验 `product: latte`，
执行 `fastboot oem unlock`（由 `fastboot.efi` 处理，并非设备 Bootloader），并在存在 `images\data.simg` 时优先刷入它。

在 Linux 上构建后，可用以下命令组装该目录：

```bash
make all VER=21
mkdir -p flash/images flash/device_files
cp DNX_flash_*.bat flash/
cp images-21/gpt.bin images-21/boot.img images-21/system.img images-21/data.img flash/images/
cp images-21/data.simg flash/images/ 2>/dev/null || true
cp overlay/boot/EFI/BlissOS/fastboot.efi flash/
cp device_files/oemvars*.txt flash/device_files/
```

> **批处理脚本的已知限制**
> - 脚本要求目录名必须为 `images/`，而 makefile 产出的是 `images-<VER>/`，
>   需按上述方式复制或重命名。
> - 脚本对 UEFI fastboot loader 的称呼与路径不一致：
>   `DNX_flash_all.bat` / `DNX_flash-boot.bat` 使用 `device_files\fastboot.efi`，
>   而 `DNX_flash-data.bat` / `DNX_flash-system.bat` 使用脚本同级的 `loader.efi`。
>   二者实为同一文件 `overlay/boot/EFI/BlissOS/fastboot.efi`，
>   请把它复制到各脚本期望的路径。
> - `dnx.7z` 目标会把镜像存放在压缩包根目录（7-Zip 会去掉目录名），
>   因此解压后**不会**得到 `images/`；请手动创建目录并移动文件，或直接采用上述结构。

## 调试

- **SSH** —— `make ssh` 会使用 `device_files/id_rsa` 以 `root@192.168.255.1` 登录。
  该功能依赖 USB gadget 网络，请把平板接到 USB 主机端口。
- **USB 网络** —— overlay 中的 `udc.sh` 会拉起 ECM gadget，并在 `192.168.255.1/24`
  上运行 `dnsmasq`；设备可通过 `adb connect 192.168.255.1:5555` 访问。
- **QEMU/KVM** —— `make qemu VER=21` 会用 virtio-gpu、virtio-net
  （宿主端口转发 `5555`/`5522`）以及一个 qcow2 数据盘启动构建产物。

## 仓库结构

```
.
├── makefile                 # 整个构建系统
├── device_files/            # 设备专用输入
│   ├── gpt.ini, gpt_ini2bin.py   # 分区表定义与生成脚本
│   ├── grub.cfg                  # GRUB 模板（替换后写入 boot.img）
│   ├── dsdt.dsl / dsdt.aml       # 修改后的 ACPI DSDT
│   ├── mipad2_keymap.c           # 电容按键重映射程序（编译为 key-remap）
│   ├── initrd*.patch             # 各版本的 initrd 补丁
│   ├── oemvars*.txt              # fastboot OEM 变量（含电池配置）
│   └── id_rsa, MOK.*             # SSH 密钥与 MOK（Machine Owner Key，安全启动）
├── overlay/
│   ├── boot/                # 原样复制进 boot.img 的文件
│   │   ├── EFI/BlissOS/     # fastboot.efi、shellx64.efi、USB gadget EFI
│   │   ├── EFI/boot/grub.cfg
│   │   └── setup_var.efi、MOK.cer  # UEFI 变量修改 + 安全启动 MOK
│   ├── system/              # 复制进 system.img 的文件
│   │   └── system/          # 固件、ALSA UCM、init 脚本、dropbear 密钥
│   ├── data/                # 复制进 data.img 的文件
│   └── system_modify.sh     # 解包后的 system 调整（build.prop、精简应用/固件）
├── build/                   # 中间产物（解包后的 ISO/initrd/system、内核、shim）
├── images-<VER>/            # 构建输出：gpt.bin、boot.img、system.img、data.img
└── DNX_flash_*.bat          # Windows 一键刷机脚本
```

## 致谢

本项目只是对他人成果的重新打包与修补：

- [BlissOS](https://blissos.org/)、[LineageOS for x86](https://lineageos-x86.github.io/)
  与 [ProjectSakura](https://projectsakura.xyz/) —— 源 Android-x86 镜像。
- [android-x86-kernel-latte](https://github.com/Qs315490/android-x86-kernel-latte) ——
  `zenith` 内核包。
- Fedora `shim` / `grub2-efi` —— 已签名的 UEFI 启动链路。

所有商标与厂商固件归各自所有者所有。
