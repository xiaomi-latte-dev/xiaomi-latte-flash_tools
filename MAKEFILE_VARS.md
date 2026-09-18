# makefile 变量说明

本文档详细说明 `makefile` 中的全部变量，按用途分类。

> 变量来源：仓库根目录的 `makefile`。
> 约定：`?=` 表示有默认值的可配置项；`:=` 表示 makefile 内部定义的计算值。
> 注意：GNU Make 中，**命令行传入的变量会覆盖文件内的两种赋值**（除非用 `override` 或 `make -e`）。

## 目录

- [1. 用户可覆盖变量](#1-用户可覆盖变量)
- [2. 版本与特性开关](#2-版本与特性开关)
- [3. 主机工具与权限](#3-主机工具与权限)
- [4. 路径变量](#4-路径变量)
- [5. 输入文件与下载来源](#5-输入文件与下载来源)
- [6. 输出产物](#6-输出产物)
- [7. 编译与打包工具链](#7-编译与打包工具链)
- [8. QEMU 变量](#8-qemu-变量)
- [9. 自动生成变量](#9-自动生成变量)
- [10. 用法示例](#10-用法示例)

---

## 1. 用户可覆盖变量

这 4 个变量使用 `?=` 定义，可直接在命令行覆盖，无需修改文件。

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `V` | `0` | 输出详细程度。`V=0` 时启用 `.SILENT:`，只显示 `echo` 的进度信息；`V=1` 时打印每条实际执行的命令，便于调试。 |
| `VER` | `14` | **目标发行版本**，是本项目的核心开关，决定源 ISO、initrd 补丁、system 压缩算法、data 挂载方式等。取值必须属于 `VER_LIST`（见下），否则 make 直接报错。 |
| `BOOT_SIZE` | `64` | `boot.img` 大小，单位 **MiB**。该镜像被格式化为 FAT32 并标记为 ESP。 |
| `DATA_SIZE` | `2048` | `data.img` 大小，单位 **MiB**。 |

示例：

```bash
make all VER=21 V=1
make all VER=21 BOOT_SIZE=64 DATA_SIZE=4096
```

---

## 2. 版本与特性开关

### `VER_LIST`

允许的 `VER` 取值（内部 `:=`）：

```make
VER_LIST := 17.1 5 14 15 16 17.2 18 21
```

makefile 会校验：

```make
ifeq ($(filter $(VER),$(VER_LIST)),)
$(error "VER must be one of $(VER_LIST)")
endif
```

各取值对应的发行版与内核（来自 makefile 顶部注释）：

| `VER` | 发行版 | Android | 内核 |
| --- | --- | --- | --- |
| `17.1` | LineageOS 17.1 | 10 | `5.8.0-android-x86_64-93451-g2eba2073e8a6` |
| `5` | ProjectSakura 5.2 | 11 | `5.10.61-GoogleLTS-xanmod1-pledge` |
| `14` | BlissOS 14.10.3 / 14.10.4 | 11 | `6.1.112-gloria-xanmod1` / `6.6.102-crimson-xanmod1` |
| `15` | BlissOS 15 | 12 | `6.1.112-gloria-xanmod1` |
| `16` | BlissOS 16 / Zenith 16 | 13 | `6.1.112-gloria-xanmod1` / `6.9.9-zenith` |
| `17.2` | BlissOS Zenith 17.2 | 14 | `6.7.10-zenith-xanmod1` |
| `18` | BlissOS 18.4 | 15 | `6.6.89-crimson-xanmod1` |
| `21` | LineageOS 21.1 | 14 | `6.12.30-zenith` |

### `NO_SUPPORT_EROFS_LIST`

不支持 EROFS 的版本列表：

```make
NO_SUPPORT_EROFS_LIST := 17 5
```

若 `VER` 命中此列表，则 `EROFS := n`，system 镜像退回 squashfs（`-comp lz4`）。

### `RAW_SYSTEM_IMAGE_LIST`

强制使用**原始（未压缩）** system 镜像的版本列表：

```make
RAW_SYSTEM_IMAGE_LIST :=
```

默认为空。若 `VER` 命中，则同时置 `EROFS := n` 和 `SQUASHFS := n`，直接 `cp` 未压缩镜像。

> 注意：`SQUASHFS` 变量**只有**在该分支才会被赋值 `n`。其余情况下它是未定义的，因此 `[ -z "$(SQUASHFS)" ]` 判断成立，即默认允许 squashfs。

### `HAVE_DROPBEAR`

```make
HAVE_DROPBEAR := n
```

是否**跳过**安装 dropbear SSH。逻辑为反向判断（`[ -z "$(HAVE_DROPBEAR)" ]`）：

| 取值 | 行为 |
| --- | --- |
| `n`（默认） | `[ -z "n" ]` 为假 → 走 else 分支 → **删除** dropbear 与 `sshd.rc` |
| 空 | `[ -z "" ]` 为真 → 安装 `dropbear` 二进制与 `authorized_keys` |

> 即：默认值 `n` 表示「系统自带 dropbear，无需本工具安装」。改为空字符串才会注入本仓库的 dropbear。

### `IMPORT_RECOVERY`

```make
IMPORT_RECOVERY := n
```

是否把 ISO 中的 `ramdisk-recovery.img` 导入 `boot.img`：

- `y`：复制到 `EFI/BlissOS/ramdisk-recovery.img`，GRUB 菜单会出现 Recovery 项。
- `n`（默认）：不导入。

### `NEW_DATA_MOUNT_LIST` 与 `NEW_DATA_MOUNT`

```make
NEW_DATA_MOUNT_LIST := 17.2 18 21
```

若 `VER` 命中该列表，则 `NEW_DATA_MOUNT := y`，否则为 `n`。它影响三处：

1. **initrd 补丁选择**：优先使用 `initrd-$(VER)-d.patch`（`-d` 后缀）。
2. **GRUB 内核参数**：`new_data_mount=y` 经 `envsubst` 传入 `grub.cfg`。
3. **QEMU 内核参数**：使用 `DATA=nodata data_part=/dev/vdb`，否则 `DATA=/dev/vdb`。

---

## 3. 主机工具与权限

这些变量为内部固定定义，用于在需要提权的操作前统一加前缀：

| 变量 | 定义 | 用途 |
| --- | --- | --- |
| `UID` | `$(shell id -u)` | 创建镜像后还原属主，避免产物属于 root |
| `GID` | `$(shell id -g)` | 同上 |
| `MOUNT` | `sudo mount` | 挂载 loop 镜像 |
| `UMOUNT` | `sudo umount` | 卸载 loop 镜像 |
| `CHOWN` | `sudo chown` | 修改镜像属主 |
| `CHMOD` | `sudo chmod` | 修改挂载点权限 |
| `INSTALL` | `sudo install` | 复制并设置权限 |
| `CP` | `sudo cp` | 复制 overlay 文件 |
| `RM` | `sudo rm -rf` | 清理挂载点内文件 |

> 说明：`UID`/`GID` 是 GNU Make 的环境变量名，这里 `:=` 赋值为当前用户的 uid/gid，用于 `truncate` 后的 `chown $(UID):$(GID)`。
> 若在**非 root** 环境构建，需要配置好 `sudo` 免密或按需输入密码。

---

## 4. 路径变量

| 变量 | 定义 | 含义 |
| --- | --- | --- |
| `PWD` | `$(shell pwd)` | 仓库根目录绝对路径 |
| `O` | `$(PWD)` | 输出根目录（即仓库根） |
| `DEVICE_FILES_DIR` | `$(PWD)/device_files` | 设备专用输入文件 |
| `IMAGES_DIR` | `$(O)/images-$(VER)` | **最终产物目录**，随 `VER` 变化 |
| `BUILD_DIR` | `$(O)/build` | 所有中间产物目录 |
| `SHIM_GRUB_DIR` | `$(BUILD_DIR)/shim_grub` | 解包后的 shim/grub RPM |
| `KERNEL_DIR` | `$(BUILD_DIR)/kernel` | 解包后的内核 |
| `ISO_DIR` | `$(BUILD_DIR)/iso-$(VER)` | 解包后的 ISO（随 `VER`） |
| `INITRD_DIR` | `$(BUILD_DIR)/initrd-$(VER)` | 解包后的 initrd（随 `VER`） |
| `BOOT_DIR` | `$(BUILD_DIR)/boot` | `boot.img` 的挂载点 |
| `SYSTEM_DIR` | `$(BUILD_DIR)/system` | system 镜像挂载点 |
| `DATA_DIR` | `$(BUILD_DIR)/data` | `data.img` 挂载点 |
| `OVERLAY_DIR` | `$(PWD)/overlay` | overlay 根目录 |
| `OVERLAY_BOOT_DIR` | `$(OVERLAY_DIR)/boot` | 复制进 `boot.img` 的文件 |
| `OVERLAY_SYSTEM_DIR` | `$(OVERLAY_DIR)/system` | 复制进 system 的文件 |
| `OVERLAY_DATA_DIR` | `$(OVERLAY_DIR)/data` | 复制进 `data.img` 的文件 |

> 这些目录无需手动创建：makefile 末尾会自动为所有 `*_DIR` 变量生成 `mkdir -p` 目标（详见[第 9 节](#9-自动生成变量)）。

---

## 5. 输入文件与下载来源

### 下载来源 URL

| 变量 | 内容 |
| --- | --- |
| `SHIM_URL` | Fedora 43 的 `shim-x64-15.8-3.x86_64.rpm` 下载地址 |
| `GRUB2_EFI_URL` | Fedora 43 的 `grub2-efi-x64-2.12-40.fc43.x86_64.rpm` 下载地址 |
| `DROPBEAR_URL` | `ribbons/android-dropbear` 的最新 release zip |

### 本地输入文件

| 变量 | 定义 | 说明 |
| --- | --- | --- |
| `SHIM_FILE` | `$(O)/shim-x64.rpm` | 缺失时自动 `wget` |
| `GRUB2_EFI_FILE` | `$(O)/grub2-efi-x64.rpm` | 缺失时自动 `wget` |
| `KERNEL_PACKAGE_FILE` | `$(wildcard kernel-*-zenith.tar.gz)` | **通配查找**，需放在仓库根 |
| `ISO_FILE` | 见下 | **通配查找** |
| `DROPBEAR_ZIP` | `$(O)/dropbear-x86_64-linux-android.zip` | 缺失时自动下载 |
| `SSH_KEY` / `SSH_KEY_PUB` | `device_files/id_rsa(.pub)` | 缺失时自动 `ssh-keygen` 生成 |
| `DSDT_FILE` | `device_files/dsdt.aml` | 由 `dsdt.dsl` 经 `iasl` 编译 |
| `GRUB_CFG_TEMPLATE` | `device_files/grub.cfg` | GRUB 配置模板 |

### `ISO_FILE` 的查找规则

```make
ifeq ($(VER),5)
ISO_FILE := $(wildcard ProjectSakura-$(VER).*.iso)
else
ISO_FILE := $(wildcard *$(VER)*-*.iso)
endif
ISO_FILE := $(firstword $(ISO_FILE))
```

- `VER=5` 特例：匹配 `ProjectSakura-5.*.iso`。
- 其他版本：匹配 `*<VER>*-*.iso`，例如 `VER=14` → `Bliss-v14.10.3-x86_64-OFFICIAL-foss-20241012.iso`。
- `$(firstword ...)` 取**第一个**匹配项。若同名规则下有多个 ISO，结果取决于文件系统通配排序——建议只保留一个匹配文件。

### `INITRD_PATCH_FILE` 的选择顺序

```make
ifeq ($(NEW_DATA_MOUNT),y)
INITRD_PATCH_FILE := $(DEVICE_FILES_DIR)/initrd-$(VER)-d.patch
endif
ifeq ($(wildcard $(INITRD_PATCH_FILE)),)
INITRD_PATCH_FILE := $(DEVICE_FILES_DIR)/initrd-$(VER).patch
endif
ifeq ($(wildcard $(INITRD_PATCH_FILE)),)
INITRD_PATCH_FILE := $(DEVICE_FILES_DIR)/initrd.patch
endif
```

按优先级回退：

1. `initrd-<VER>-d.patch`（仅当 `NEW_DATA_MOUNT=y`）
2. `initrd-<VER>.patch`
3. `initrd.patch`（通用兜底）

---

## 6. 输出产物

| 变量 | 定义 | 产物 |
| --- | --- | --- |
| `BOOT_FILE` | `$(IMAGES_DIR)/boot.img` | FAT32 ESP，含 shim + GRUB + 内核 + initrd |
| `SYSTEM_FILE` | `$(IMAGES_DIR)/system.img` | erofs / squashfs / 原始镜像 |
| `DATA_FILE` | `$(IMAGES_DIR)/data.img` | f2fs（优先）或 ext4 |
| `GPT_FILE` | `$(IMAGES_DIR)/gpt.bin` | GPT 分区表 |
| （无变量） | `$(IMAGES_DIR)/data.simg` | `img2simg` 生成的稀疏镜像，工具缺失则跳过 |

### 中间产物与时间戳

| 变量 | 定义 | 说明 |
| --- | --- | --- |
| `INITRD_FILE` | `$(BUILD_DIR)/initrd-$(VER).cpio.gz` | 打包后的 initrd |
| `SHIM_GRUB_STAMP` | `$(BUILD_DIR)/.shim-grub.stamp` | 解包完成标记 |
| `KERNEL_STAMP` | `$(KERNEL_DIR)/.stamp` | 内核解包完成标记 |
| `ISO_STAMP` | `$(ISO_DIR)/.stamp` | ISO 解包完成标记 |
| `INITRD_STAMP` | `$(BUILD_DIR)/.initrd-$(VER).stamp` | initrd 解包完成标记 |
| `INITRD_PATCH_STAMP` | `$(BUILD_DIR)/.initrd-$(VER).patch.stamp` | initrd 补丁完成标记 |
| `SYSTEM_UNCOMP_DIR` | `$(BUILD_DIR)/system_uncomp_$(VER)` | 未压缩 system 的解包目录 |
| `SYSTEM_UNCOMP_FILE` | `$(SYSTEM_UNCOMP_DIR)/system.img` | 未压缩 system 镜像 |
| `KEY_REMAP_PROG` | `$(BUILD_DIR)/key-remap` | 由 `mipad2_keymap.c` 静态编译 |
| `DROPBEAR_FILE` | `$(BUILD_DIR)/dropbear` | 解压出的 dropbear 二进制 |

> 这些 `.stamp` / `.patch.stamp` 文件即 Make 的「已完成」标记：删除它们可强制对应步骤重跑。

---

## 7. 编译与打包工具链

| 变量 | 默认 | 作用 |
| --- | --- | --- |
| `EROFS` | 空 | 置 `n` 时**禁用** erofs，回退 squashfs |
| `SQUASHFS` | 未定义 | 仅在 `RAW_SYSTEM_IMAGE_LIST` 命中时置 `n`，禁用 squashfs |
| `SQUASHFS_COMP` | `-comp lz4` | squashfs 压缩参数。文件中还注释了 `xz`、`zstd` 备选方案 |
| `F2FS` | 空 | 置非空时**强制** `data.img` 使用 ext4 而非 f2fs |

### system 镜像压缩决策

```make
mkfs.erofs ... -zzstd,level=1        # 若 mkfs.erofs 存在且 EROFS 为空
mksquashfs ... -b 1M $(SQUASHFS_COMP) # 否则若 mksquashfs 存在且 SQUASHFS 为空
cp $(SYSTEM_UNCOMP_FILE) "$@"         # 都没有：直接复制未压缩镜像
```

### data 镜像文件系统决策

```make
mkfs.f2fs -l userdata -O extra_attr,inode_checksum,sb_checksum,compression -f  # mkfs.f2fs 存在且 F2FS 为空
mkfs.ext4 -L userdata -F                                                         # 否则
```

> `SQUASHFS_COMP` 与 `EROFS`/`SQUASHFS` 均由 `VER` 间接决定，一般无需手动改。

---

## 8. QEMU 变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `QEMU_VIRGL` | `y` | 置 `n` 时追加 `nomodeset HWACCEL=0`，用于无硬件加速环境 |
| `QEMU_DEBUG` | `0` | 为 `0` 时追加内核参数 `quiet`；同时影响 `DEBUG=` 值 |
| `KVM` | `y` | 置 `y` 时使用 `-enable-kvm` |
| `QEMU_MEM` | `2000` | 虚拟机内存，单位 MiB |
| `KERNEL_DEFAULT_CMDLINE` | 见下 | 默认内核命令行 |
| `EXTRA_KERNEL_CMDLINE` | 空 | 供追加自定义参数的钩子 |
| `QEMU_KERNEL_CMDLINE` | 组合值 | `KERNEL_DEFAULT_CMDLINE` + `EXTRA_KERNEL_CMDLINE` + 条件项 |
| `QEMU_KVM` | 条件值 | `KVM=y` 时为 `-enable-kvm`，否则为空 |
| `QEMU_KERNEL_FILE` | `$(wildcard $(KERNEL_DIR)/vmlinuz-*)` | 从内核目录自动查找 |
| `QEMU_INITRD_FILE` | `$(INITRD_FILE)` | 复用打包好的 initrd |
| `QEMU_SYSTEM_FILE` | `$(SYSTEM_FILE)` | 复用 `system.img` |
| `QEMU_DATA_FILE` | `$(BUILD_DIR)/data.qcow2` | 由 `data.img` 转换而来 |

默认内核命令行：

```
console=tty1 console=ttyS0,115200 androidboot.enable_console=1 SRC=. DEBUG=$(QEMU_DEBUG) VIRT_WIFI=1 video=1280x720
```

再根据 `NEW_DATA_MOUNT` 追加 `DATA=...`，并按 `QEMU_VIRGL` / `QEMU_DEBUG` 追加对应参数。

> 以上 QEMU 变量均为 `:=`，但**仍可在命令行覆盖**（GNU Make 命令行优先级高于文件内赋值），例如 `make qemu QEMU_VIRGL=n QEMU_MEM=4096`。
> 若需长期生效，直接编辑 makefile 即可。

---

## 9. 自动生成变量

makefile 末尾自动为所有目录变量创建 `mkdir -p` 目标：

```make
DIR_VARS := $(filter %_DIR,$(.VARIABLES)) $(O)
ALL_DIRS := $(foreach v,$(DIR_VARS),$($(v)))
$(ALL_DIRS):
	mkdir -p $@
```

含义：

- `$(.VARIABLES)` 是 Make 内建函数，列出当前定义的全部变量名。
- `$(filter %_DIR,...)` 筛出所有以 `_DIR` 结尾的变量名。
- `$(foreach v,...,$($(v)))` 再把「变量名」展开成其「值」（即实际路径）。
- 追加 `$(O)` 保证输出根目录存在。
- 于是每个路径都成为一条 `mkdir -p` 规则，且作为 `order-only` 前置依赖（`|`）使用，避免重复触发重建。

> 因此**新增**一个形如 `XXX_DIR := ...` 的变量后，无需手动编写目录创建规则。

---

## 10. 用法示例

```bash
# 用默认 VER=14 构建全部产物
make

# 指定版本并显示完整命令
make all VER=21 V=1

# 调整镜像大小
make all VER=21 BOOT_SIZE=64 DATA_SIZE=4096

# 强制 data.img 用 ext4（F2FS 非空）
make data.img VER=21 F2FS=n

# 在 QEMU 中运行（KVM=y 默认开启）
make qemu VER=21

# 无硬件加速环境
make qemu VER=21 QEMU_VIRGL=n

# 清空构建目录与镜像
make clean_all

# 只清理当前版本的镜像目录
make clean_images VER=21
```

> 提示：GNU Make 中**命令行传入的变量会覆盖 makefile 里的 `:=` 赋值**（除非使用 `override` 或 `make -e`）。
> 因此表格中的变量原则上都可在命令行临时覆盖，例如 
> `make all VER=21 IMPORT_RECOVERY=y HAVE_DROPBEAR= QEMU_MEM=4096`。
> 但部分是「按需计算」的派生变量（如由 `VER` 推导的 `EROFS`、`SQUASHFS_COMP`、`NEW_DATA_MOUNT`），
> 直接覆盖可能与其推导逻辑冲突，建议优先调整输入变量（如 `VER`）而非结果变量。
