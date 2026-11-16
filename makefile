V ?= 0
ifeq ($(V),0)
.SILENT:
endif

# 不带参数直接 make 等于完整构建
.DEFAULT_GOAL := all

# LineageOS 21.1	为 Android 14 6.12.30-zenith
# LineageOS 17.1	为 Android 10 5.8.0-android-x86_64-93451-g2eba2073e8a6
# ProjectSakura-5.2	为 Android 11 5.10.61-GoogleLTS-xanmod1-pledge
# BlissOS 14.10.3	为 Android 11 6.1.112-gloria-xanmod1
# BlissOS 14.10.4	为 Android 11 6.6.102-crimson-xanmod1
# BlissOS 15		为 Android 12 6.1.112-gloria-xanmod1
# BlissOS 16		为 Android 13 6.1.112-gloria-xanmod1
# BlissOS-Zenith 16	为 Android 13 6.9.9-zenith
# BlissOS-Zenith17.2为 Android 14 6.7.10-zenith-xanmod1
# BlissOS 18.4		为 Android 15 6.6.89-crimson-xanmod1
# 系统标识命名：BlissOS 为 v<大版本>（v14/v15/v16/v17/v18，17 对应 17.2）；
# Lineage 为 los<版本>（los17=17.1，los21）；Sakura 为 sk<版本>（sk5）。
VER_LIST := los17 sk5 v14 v15 v16 v17 los21 v18
VER ?= v14
# 判断输入版本是否在范围内
ifeq ($(filter $(VER),$(VER_LIST)),)
$(error "VER must be one of $(VER_LIST)")
endif

# 数字版本：ISO 文件名匹配与 device_files/initrd-<num>*.patch 沿用旧数字命名。
ifeq ($(VER),los17)
VER_NUM := 17.1
else ifeq ($(VER),sk5)
VER_NUM := 5
else ifeq ($(VER),v14)
VER_NUM := 14
else ifeq ($(VER),v15)
VER_NUM := 15
else ifeq ($(VER),v16)
VER_NUM := 16
else ifeq ($(VER),v17)
VER_NUM := 17.2
else ifeq ($(VER),los21)
VER_NUM := 21
else ifeq ($(VER),v18)
VER_NUM := 18
endif

# 注：原表里的 "17" 因 filter 词匹配从未命中 17.1/17.2，按意图归到 los17。
NO_SUPPORT_EROFS_LIST := los17 sk5
RAW_SYSTEM_IMAGE_LIST := 
HAVE_DROPBEAR := n
IMPORT_RECOVERY := n
NEW_DATA_MOUNT_LIST := v17 v18 los21
ifeq ($(filter $(VER),$(NEW_DATA_MOUNT_LIST)),)
NEW_DATA_MOUNT := n
else
NEW_DATA_MOUNT := y
endif

UID := $(shell id -u)
GID := $(shell id -g)
MOUNT := sudo mount
UMOUNT := sudo umount
CHOWN := sudo chown
CHMOD := sudo chmod
INSTALL := sudo install
CP := sudo cp
RM := sudo rm -rf

BOOT_SIZE ?= 64
DATA_SIZE ?= 2048

PWD = $(shell pwd)
DEVICE_FILES_DIR := $(PWD)/device_files

# 输出文件夹
O := $(PWD)
IMAGES_DIR := $(O)/images-$(VER)
BUILD_DIR := $(O)/build
SHIM_GRUB_DIR := $(BUILD_DIR)/shim_grub
KERNEL_DIR := $(BUILD_DIR)/kernel
ISO_DIR := $(BUILD_DIR)/iso-$(VER)
INITRD_DIR := $(BUILD_DIR)/initrd-$(VER)
BOOT_DIR := $(BUILD_DIR)/boot
SYSTEM_DIR := $(BUILD_DIR)/system
DATA_DIR := $(BUILD_DIR)/data

OVERLAY_DIR := $(PWD)/overlay
OVERLAY_BOOT_DIR := $(OVERLAY_DIR)/boot
OVERLAY_SYSTEM_DIR := $(OVERLAY_DIR)/system
OVERLAY_DATA_DIR := $(OVERLAY_DIR)/data

# 音频 HAL 修复（XRUN 恢复 + 高水位）。原 HAL 在欠载后陷入 -EPIPE 循环，
# 播放约 20 分钟必然断音（50ms 风暴）。产物来自 ../libaudio-xrun-fix（源码
# android-generic/platform_hardware_libaudio 对应分支 + 0001/0002 补丁），
# 位数与安装路径按系统不同，因此按 VER 映射而非进 system_modify.sh（该脚本
# 所有版本共用）。无产物映射的 VER 跳过安装。
AUDIO_HAL_DIR := $(DEVICE_FILES_DIR)/audio-hal
ifeq ($(VER),v14)
AUDIO_HAL_FILE := $(AUDIO_HAL_DIR)/v14.so
AUDIO_HAL_PATH := /system/lib/hw/audio.primary.x86.so
else ifeq ($(VER),sk5)
AUDIO_HAL_FILE := $(AUDIO_HAL_DIR)/sk5.so
AUDIO_HAL_PATH := /system/lib/hw/audio.primary.x86.so
else ifeq ($(VER),v16)
AUDIO_HAL_FILE := $(AUDIO_HAL_DIR)/v16.so
AUDIO_HAL_PATH := /system/lib/hw/audio.primary.x86.so
else ifeq ($(VER),los21)
AUDIO_HAL_FILE := $(AUDIO_HAL_DIR)/los21.so
AUDIO_HAL_PATH := /system/vendor/lib64/hw/audio.primary.x86.so
endif

# Fedora 44 的 EFI/BOOT 目录直接提供 EFI 文件，无需解包 rpm。
# 注意该目录没有 fbx64.efi（Fedora 43 的 rpm 里有），因此不再安装它。
SHIM_BASE_URL := https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/EFI/BOOT

SHIM_BOOTX64 := $(SHIM_GRUB_DIR)/BOOTX64.EFI
SHIM_GRUBX64 := $(SHIM_GRUB_DIR)/grubx64.efi
SHIM_MMX64 := $(SHIM_GRUB_DIR)/mmx64.efi

$(SHIM_BOOTX64) $(SHIM_GRUBX64) $(SHIM_MMX64): | $(SHIM_GRUB_DIR)
	# 先下到临时文件再改名：wget 中断会留下截断文件。直接写目标会让 make 把
	# 截断文件当成已完成，后续签名和引导都基于坏文件。
	TMP_DL="$@.part"; \
	rm -f "$$TMP_DL"; \
	wget --quiet "$(SHIM_BASE_URL)/$(@F)" -O "$$TMP_DL"; \
	[ -s "$$TMP_DL" ] || { echo "下载失败: $@" >&2; rm -f "$$TMP_DL"; exit 1; }; \
	mv -f "$$TMP_DL" "$@"

# shim 在 .vendor_cert 段内嵌 fedoraca 证书，这是它信任 grub 的依据。
# 用它判断 grub 是否有「shim 认可的签名」，避免被本机系统密钥环（通常没有
# fedoraca）误判成未签名，从而每次都不必要地重签。
SHIM_VENDOR_CERT := $(SHIM_GRUB_DIR)/vendor.pem
$(SHIM_VENDOR_CERT): $(SHIM_BOOTX64) | $(SHIM_GRUB_DIR)
	./scripts/shim-vendor-cert.sh "$(SHIM_BOOTX64)" "$@"

# Secure Boot 下 shim 会校验内核签名，内核必须用本仓库 MOK 签过。
MOK_KEY := $(DEVICE_FILES_DIR)/MOK.key
MOK_CERT := $(DEVICE_FILES_DIR)/MOK.crt

SHIM_GRUB_STAMP := $(BUILD_DIR)/.shim-grub.stamp
$(SHIM_GRUB_STAMP): $(SHIM_BOOTX64) $(SHIM_GRUBX64) $(SHIM_MMX64) | $(SHIM_GRUB_DIR)
	touch $@
unpack_shim_grub: $(SHIM_GRUB_STAMP)
clean_shim_grub:
	$(RM) "$(SHIM_GRUB_STAMP)"
	$(RM) -r "$(SHIM_GRUB_DIR)"
.PHONY: unpack_shim_grub clean_shim_grub

KERNEL_PACKAGE_FILE := $(wildcard kernel-*-zenith.tar.gz)
KERNEL_STAMP := $(KERNEL_DIR)/.stamp
$(KERNEL_STAMP): $(KERNEL_PACKAGE_FILE) | $(KERNEL_DIR)
	echo "解包内核文件:" $<
	tar -xzf $< -C "$(KERNEL_DIR)"
	touch $@
	echo "解包内核文件:" "完成"
unpack_kenrel: $(KERNEL_STAMP)
clean_kenrel:
	$(RM) "$(KERNEL_DIR)" "$(KERNEL_STAMP)"
.PHONY: unpack_kenrel clean_kenrel

ifeq ($(VER),sk5)
ISO_FILE := $(wildcard ProjectSakura-$(VER_NUM).*.iso)
else
ISO_FILE := $(wildcard *$(VER_NUM)*-*.iso)
endif
ISO_FILE := $(firstword $(ISO_FILE))
ISO_STAMP := $(ISO_DIR)/.stamp
$(ISO_STAMP): $(ISO_FILE) | $(ISO_DIR)
	echo "解包ISO文件:" $<
	7z x -aos -o"$(ISO_DIR)" "$<"
	touch $@
	echo "解包ISO文件:" "完成"
unpack_iso: $(ISO_STAMP)
clean_iso:
	$(RM) "$(ISO_DIR)" "$(ISO_STAMP)"
.PHONY: unpack_iso clean_iso

DSDT_FILE := $(DEVICE_FILES_DIR)/dsdt.aml
$(DSDT_FILE): $(DEVICE_FILES_DIR)/dsdt.dsl
	iasl -ve -ts -w1 "$<"

INITRD_FILE := $(BUILD_DIR)/initrd-$(VER).cpio.gz
INITRD_STAMP := $(BUILD_DIR)/.initrd-$(VER).stamp
ifeq ($(NEW_DATA_MOUNT),y)
INITRD_PATCH_FILE := $(DEVICE_FILES_DIR)/initrd-$(VER_NUM)-d.patch
endif
ifeq ($(wildcard $(INITRD_PATCH_FILE)),)
INITRD_PATCH_FILE := $(DEVICE_FILES_DIR)/initrd-$(VER_NUM).patch
endif
ifeq ($(wildcard $(INITRD_PATCH_FILE)),)
INITRD_PATCH_FILE := $(DEVICE_FILES_DIR)/initrd.patch
endif
INITRD_PATCH_STAMP := $(BUILD_DIR)/.initrd-$(VER).patch.stamp
$(INITRD_STAMP): $(ISO_STAMP)
	echo "解包initrd文件"
	$(RM) "$(INITRD_DIR)"
	mkdir -p "$(INITRD_DIR)"
	zcat "$(ISO_DIR)/initrd.img" | (cd "$(INITRD_DIR)" && cpio -id)
	touch $@
	echo "解包initrd文件:" "完成"
unpack_initrd: $(INITRD_STAMP)
$(INITRD_PATCH_STAMP): $(INITRD_STAMP) $(INITRD_PATCH_FILE) $(DSDT_FILE)
	echo "initrd 打补丁"
	patch -p1 < $(INITRD_PATCH_FILE) -d "$(INITRD_DIR)"
	sed -i 's|bliss.model="$$BOARD"|bliss.model="$$PRODUCT"|' "$(INITRD_DIR)/init"
	$(INSTALL) -Dm755 "$(DSDT_FILE)" "$(INITRD_DIR)/kernel/firmware/acpi/dsdt.aml"
	touch $@
	echo "initrd 打补丁:" "完成"
patch_initrd: $(INITRD_PATCH_STAMP)
$(INITRD_FILE): $(INITRD_PATCH_STAMP)
	echo "initrd 打包"
	cd "$(INITRD_DIR)";find . | cpio -o -H newc | gzip > "$(INITRD_FILE)"
	echo "initrd 打包:" "完成"
pack_initrd: $(INITRD_FILE)
clean_initrd:
	$(RM) "$(INITRD_DIR)" "$(INITRD_FILE)" "$(INITRD_STAMP)" "$(INITRD_PATCH_STAMP)"
.PHONY: unpack_initrd patch_initrd pack_initrd

GRUB_CFG_TEMPLATE := $(DEVICE_FILES_DIR)/grub.cfg
BOOT_FILE := $(IMAGES_DIR)/boot.img
$(BOOT_FILE): $(OVERLAY_BOOT_DIR) $(SHIM_GRUB_STAMP) $(SHIM_VENDOR_CERT) $(INITRD_FILE) $(KERNEL_STAMP) $(GRUB_CFG_TEMPLATE) | $(IMAGES_DIR) $(BOOT_DIR)
	echo "打包boot.img"
	if grep -q "$(BOOT_DIR)" /proc/mounts;then $(UMOUNT) "$(BOOT_DIR)";fi
	sudo truncate -s $(BOOT_SIZE)M "$@"
	$(CHOWN) $(UID):$(GID) "$@"
	mkfs.vfat -F 32 -n ESP "$@"
	$(MOUNT) -o loop "$@" "$(BOOT_DIR)"
	# shim 与 MOK 管理器：保持微软签名，不能重签。
	$(INSTALL) -D "$(SHIM_BOOTX64)" "$(BOOT_DIR)/EFI/boot/bootx64.efi"
	$(INSTALL) -D "$(SHIM_MMX64)" "$(BOOT_DIR)/EFI/boot/mmx64.efi"
	# GRUB：官方 grubx64.efi 由 fedoraca 签名，配套 shim 可直接加载，此时原样
	# 拷贝；只有签名不被 shim 认可（或压根没签名）时才用本仓库 MOK 重签。
	# 注意不能用无参数的 sbverify 判断——它查的是本机系统密钥环，通常没有
	# fedoraca，会把官方签名误判为无效。
	GRUB_SRC="$(SHIM_GRUBX64)"; GRUB_DST="$(BUILD_DIR)/grubx64.efi"; \
	if command -v sbverify >/dev/null 2>&1 && [ -f "$(SHIM_VENDOR_CERT)" ] && \
	   sbverify --cert "$(SHIM_VENDOR_CERT)" "$$GRUB_SRC" >/dev/null 2>&1; then \
		echo "grubx64.efi 已由 fedoraca 签名，原样拷贝" >&2; \
		cp -f "$$GRUB_SRC" "$$GRUB_DST"; \
	elif command -v sbsign >/dev/null 2>&1 && [ -f "$(MOK_KEY)" ] && [ -f "$(MOK_CERT)" ]; then \
		echo "grubx64.efi 未被 shim 认可，使用 MOK 重签" >&2; \
		sbsign --key "$(MOK_KEY)" --cert "$(MOK_CERT)" --output "$$GRUB_DST" "$$GRUB_SRC"; \
	else \
		echo "警告：grubx64.efi 签名不可用，Secure Boot 下无法引导" >&2; \
		cp -f "$$GRUB_SRC" "$$GRUB_DST"; \
	fi
	$(INSTALL) -D "$(BUILD_DIR)/grubx64.efi" "$(BOOT_DIR)/EFI/boot/grubx64.efi"
	$(INSTALL) -D "$(INITRD_FILE)" "$(BOOT_DIR)/EFI/BlissOS/initrd.cpio.gz"
	# 内核：Secure Boot 下 shim 会校验内核签名，必须由本仓库 MOK 签过。
	KSRC=$(KERNEL_DIR)/vmlinuz-*; KIMG="$(BUILD_DIR)/vmlinuz"; \
	if command -v sbverify >/dev/null 2>&1 && [ -f "$(MOK_CERT)" ] && \
	   sbverify --cert "$(MOK_CERT)" $$KSRC >/dev/null 2>&1; then \
		echo "内核已有有效 MOK 签名，复用" >&2; \
		cp -f $$KSRC "$$KIMG"; \
	elif command -v sbsign >/dev/null 2>&1 && [ -f "$(MOK_KEY)" ] && [ -f "$(MOK_CERT)" ]; then \
		echo "内核未签名或签名不匹配，使用 MOK 重签" >&2; \
		sbsign --key "$(MOK_KEY)" --cert "$(MOK_CERT)" --output "$$KIMG" $$KSRC; \
	else \
		echo "警告：sbsign 或 MOK 密钥缺失，内核未签名，Secure Boot 下无法引导" >&2; \
		cp -f $$KSRC "$$KIMG"; \
	fi
	$(INSTALL) -D "$(BUILD_DIR)/vmlinuz" "$(BOOT_DIR)/EFI/BlissOS/vmlinuz"
	[ "$(IMPORT_RECOVERY)" = "y" ] && $(INSTALL) -D "$(ISO_DIR)"/ramdisk-recovery.img "$(BOOT_DIR)/EFI/BlissOS/ramdisk-recovery.img" || true
	$(CP) -r "$(OVERLAY_BOOT_DIR)"/* "$(BOOT_DIR)"
	new_data_mount=$(NEW_DATA_MOUNT) envsubst '$$new_data_mount' < "$(GRUB_CFG_TEMPLATE)" | sudo tee "$(BOOT_DIR)/EFI/BlissOS/grub.cfg" > /dev/null;
	$(CHMOD) -R 644 "$(BOOT_DIR)/"
	$(UMOUNT) "$(BOOT_DIR)"
	echo "打包boot.img:" "完成"
boot.img: $(BOOT_FILE)
mount_boot: $(BOOT_FILE) umount_boot
	$(MOUNT) -o loop "$<" "$(BOOT_DIR)"
umount_boot:
	$(UMOUNT) "$(BOOT_DIR)" || echo "未挂载boot.img"
clean_boot: umount_boot
	$(RM) "$(BOOT_FILE)"
.PHONY: boot.img mount_boot umount_boot clean_boot

F2FS :=
DATA_FILE := $(IMAGES_DIR)/data.img
$(DATA_FILE): $(OVERLAY_DATA_DIR) | $(IMAGES_DIR) $(DATA_DIR)
	echo "打包data.img"
	if grep -q "$(DATA_DIR)" /proc/mounts;then $(UMOUNT) "$(DATA_DIR)";fi
	sudo truncate -s $(DATA_SIZE)M "$@"
	$(CHOWN) $(UID):$(GID) "$@"
	if (command -v mkfs.f2fs &> /dev/null) && [ -z "$(F2FS)" ];then \
        echo "f2fs-tools found, using f2fs for data image."; \
        sudo mkfs.f2fs -l userdata -O extra_attr,inode_checksum,sb_checksum,compression -f "$@"; \
    else \
        echo "f2fs-tools not found, using ext4 for data image."; \
        sudo mkfs.ext4 -L userdata -F "$@"; \
    fi
	$(MOUNT) -o loop "$@" "$(DATA_DIR)"
	$(CP) -r "$(OVERLAY_DATA_DIR)/"* "$(DATA_DIR)" || echo OVERLAY_DATA_DIR为空, 跳过复制.
	$(CHMOD) -R 755 "$(DATA_DIR)/"
	$(UMOUNT) "$(DATA_DIR)"
	if command -v img2simg &> /dev/null; then \
        img2simg "$@" "$(IMAGES_DIR)/data.simg"; \
    else \
        echo "img2simg not found, skipping sparse conversion."; \
    fi
	echo "打包data.img:" "完成"
data.img: $(DATA_FILE)
mount_data: $(DATA_FILE) umount_data
	$(MOUNT) -o loop "$<" "$(DATA_DIR)"
umount_data:
	$(UMOUNT) "$(DATA_DIR)" || echo "未挂载data.img"
clean_data: umount_data
	$(RM) "$(DATA_FILE)" "$(IMAGES_DIR)/data.simg"
.PHONY: data.img mount_data umount_data clean_data

# key-remap 必须用 NDK（bionic）编译，不能用主机 gcc -static。
#
# 主机 glibc 的静态库带 IFUNC 变体，其中包含 AVX/AVX2 实现。Mi Pad 2 的
# Airmont（Atom x5-Z8500）连 AVX 都不支持，一旦 glibc 的 IFUNC 选错实现，
# 进程启动后立刻 SIGILL —— 连最简的 printf 都会崩。这不是 -march 能解决的：
# -march 只影响本文件生成的指令，libc.a 是预编译机器码，编译器不会再动它；
# 静态链接下 GLIBC_TUNABLES 也来不及在 _dl_start 的 IFUNC 解析前生效。
#
# NDK 的 bionic 没有 IFUNC，基线就是 x86-64，strip 后约 713K（比 glibc 版更小）。
NDK_ROOT ?= /opt/android-ndk
NDK_HOST_TAG ?= linux-x86_64
NDK_BIN := $(NDK_ROOT)/toolchains/llvm/prebuilt/$(NDK_HOST_TAG)/bin
NDK_CC := $(NDK_BIN)/x86_64-linux-android21-clang
NDK_STRIP := $(NDK_BIN)/llvm-strip

KEY_REMAP_PROG := $(BUILD_DIR)/key-remap
$(KEY_REMAP_PROG): $(DEVICE_FILES_DIR)/mipad2_keymap.c | $(BUILD_DIR)
	@[ -x "$(NDK_CC)" ] || { \
		echo "错误: 找不到 $(NDK_CC)" >&2; \
		echo "请安装 Android NDK，或用 NDK_ROOT=... 指定路径。" >&2; \
		echo "不要改用 gcc -static：主机 glibc 会用 AVX 指令，本机启动即 SIGILL。" >&2; \
		exit 1; \
	}
	"$(NDK_CC)" -O2 -Wall -o "$@" "$<" -static
	"$(NDK_STRIP)" --strip-all "$@"

DROPBEAR_URL := https://github.com/ribbons/android-dropbear/releases/latest/download/dropbear-x86_64-linux-android.zip
DROPBEAR_ZIP := $(O)/dropbear-x86_64-linux-android.zip
DROPBEAR_FILE := $(BUILD_DIR)/dropbear
$(DROPBEAR_ZIP): | $(O)
	wget --quiet $(DROPBEAR_URL) -O "$@"
$(DROPBEAR_FILE): $(DROPBEAR_ZIP) | $(BUILD_DIR)
	unzip "$<" -d "$(BUILD_DIR)" dropbear
	touch $@

EROFS :=
# SQUASHFS_COMP := -comp xz -Xdict-size 1M
# SQUASHFS_COMP := -comp zstd -Xcompression-level 15
SQUASHFS_COMP := -comp lz4
ifneq ($(filter $(VER),$(NO_SUPPORT_EROFS_LIST)),)
EROFS := n
SQUASHFS_COMP := -comp lz4
else ifneq ($(filter $(VER),$(RAW_SYSTEM_IMAGE_LIST)),)
EROFS := n
SQUASHFS := n
endif
SYSTEM_FILE := $(IMAGES_DIR)/system.img
SYSTEM_UNCOMP_DIR := $(BUILD_DIR)/system_uncomp_$(VER)
SYSTEM_UNCOMP_FILE := $(SYSTEM_UNCOMP_DIR)/system.img
$(SYSTEM_UNCOMP_FILE): $(ISO_STAMP) | $(SYSTEM_UNCOMP_DIR)
	echo "解包system.img"
	if [ -f "$(SYSTEM_UNCOMP_FILE)" ]; then \
        $(RM) "$(SYSTEM_UNCOMP_FILE)"; \
    fi
	if [ -f "$(ISO_DIR)/system.sfs" ]; then \
        unsquashfs -d "$(SYSTEM_UNCOMP_DIR)" "$(ISO_DIR)/system.sfs"; \
    elif [ -f "$(ISO_DIR)/system.efs" ]; then \
		$(RM) "$(SYSTEM_UNCOMP_DIR)"/*.txt*; \
        fsck.erofs --extract="$(SYSTEM_UNCOMP_DIR)/" "$(ISO_DIR)/system.efs"; \
    fi
	touch $@
	echo "解包system.img:" "完成"
unpack_system: $(SYSTEM_UNCOMP_FILE)
$(SYSTEM_FILE): $(OVERLAY_SYSTEM_DIR) $(SYSTEM_UNCOMP_FILE) $(KERNEL_STAMP) $(KEY_REMAP_PROG) \
				$(DROPBEAR_FILE) $(SSH_KEY_PUB) $(AUDIO_HAL_FILE) | $(SYSTEM_DIR) $(IMAGES_DIR)
	echo "修改system"
	if grep -q "$(SYSTEM_DIR)" /proc/mounts;then $(UMOUNT) "$(SYSTEM_DIR)";fi
	$(MOUNT) -o loop "$(SYSTEM_UNCOMP_FILE)" "$(SYSTEM_DIR)"

	$(RM) "$(SYSTEM_DIR)/system/lib/modules"
	$(INSTALL) -dm755 "$(SYSTEM_DIR)/system/lib/modules"
	$(CP) -r "$(KERNEL_DIR)/lib/modules/"* "$(SYSTEM_DIR)/system/lib/modules"

	$(INSTALL) --strip -Dm755 "$(KEY_REMAP_PROG)" "$(SYSTEM_DIR)/system/bin/key-remap"

	cd "$(SYSTEM_DIR)"; if [ -f "$(OVERLAY_DIR)/system_modify.sh" ]; then sudo sh "$(OVERLAY_DIR)/system_modify.sh"; fi
	$(CP) -r "$(OVERLAY_SYSTEM_DIR)/"* "$(SYSTEM_DIR)" || echo OVERLAY_SYSTEM_DIR为空, 跳过复制.

	if [ -n "$(AUDIO_HAL_FILE)" ]; then \
		$(INSTALL) -Dm755 "$(AUDIO_HAL_FILE)" "$(SYSTEM_DIR)$(AUDIO_HAL_PATH)"; \
	else \
		echo "VER=$(VER) 无音频 HAL 修复产物, 跳过"; \
	fi

	if [ -z "$(HAVE_DROPBEAR)" ];then \
		$(INSTALL) --strip -Dm755 "$(DROPBEAR_FILE)" "$(SYSTEM_DIR)/system/bin/dropbear";\
		$(INSTALL) -Dm755 "$(SSH_KEY_PUB)" "$(SYSTEM_DIR)/system/etc/dropbear/authorized_keys";\
	else \
		$(RM) -rf "$(SYSTEM_DIR)/system/etc/dropbear";\
		$(RM) -rf "$(SYSTEM_DIR)/system/etc/init/udc.latte.rc";\
	fi

	$(CHMOD) -R 755 "$(SYSTEM_DIR)/"

	echo "修改system:" "完成"
	echo "打包system.img"
	$(UMOUNT) "$(SYSTEM_DIR)" || true
	$(RM) "$(SYSTEM_UNCOMP_DIR)"/*.txt*;
	if (command -v mkfs.erofs &> /dev/null) && [ -z "$(EROFS)" ];then \
        echo "erofs-utils found, using erofs for system image."; \
        mkfs.erofs -L system -zzstd,level=1 "$@" "$(SYSTEM_UNCOMP_DIR)"; \
    elif (command -v mksquashfs &> /dev/null) && [ -z "$(SQUASHFS)" ];then \
        echo "squashfs-tools found, using squashfs for system image."; \
        mksquashfs "$(SYSTEM_UNCOMP_DIR)" "$@" -b 1M $(SQUASHFS_COMP) -noappend; \
    else \
        echo "erofs-utils and squashfs-tools not found, no package"; \
        cp "$(SYSTEM_UNCOMP_FILE)" "$@"; \
    fi
	touch $@
	echo "打包system.img:" "完成"
pack_system system.img: $(SYSTEM_FILE)
mount_system: $(SYSTEM_UNCOMP_FILE) umount_system
	$(MOUNT) -o loop "$<" "$(SYSTEM_DIR)"
umount_system:
	$(UMOUNT) "$(SYSTEM_DIR)" || echo "未挂载system.img"
clean_system:
	$(RM) $(SYSTEM_UNCOMP_FILE) $(SYSTEM_UNCOMP_DIR)/system.img $(SYSTEM_UNCOMP_DIR)/system_image_info.txt
.PHONY: unpack_system pack_system system.img mount_system umount_system clean_system

GPT_FILE := $(IMAGES_DIR)/gpt.bin
$(GPT_FILE): $(DEVICE_FILES_DIR)/gpt.ini | $(IMAGES_DIR)
	python3 "$(DEVICE_FILES_DIR)/gpt_ini2bin.py" -c "$<" "$@"
	echo "生成gpt.bin: 完成"
gpt.bin: $(GPT_FILE)
.PHONY: gpt.bin

clean: umount_boot umount_system umount_data
	$(RM) $(BUILD_DIR)
clean_images:
	$(RM) $(IMAGES_DIR)
clean_all: clean
	$(RM) $(O)/images*/
.PHONY: clean clean_images clean_all

flash_gpt: $(GPT_FILE)
	fastboot flash gpt "$<"
flash_boot: $(BOOT_FILE)
	fastboot flash boot "$<"
flash_system: $(SYSTEM_FILE)
	fastboot flash system "$<"
flash_data: $(DATA_FILE)
	fastboot flash data "$<"
flash_boot_system: flash_boot flash_system
flash_reboot:
	fastboot reboot
flash_all: flash_gpt flash_boot flash_system flash_data flash_reboot
.PHONY: flash_gpt flash_boot flash_system flash_boot_system flash_data flash_reboot flash_all

all: gpt.bin boot.img system.img data.img
.PHONY: all

SSH_KEY := $(DEVICE_FILES_DIR)/id_rsa
SSH_KEY_PUB := $(DEVICE_FILES_DIR)/id_rsa.pub
$(SSH_KEY) $(SSH_KEY_PUB): | $(DEVICE_FILES_DIR)
	ssh-keygen -t rsa -N "" -f "$@"

ssh: $(SSH_KEY)
# 依赖 内核 PTY 支持
	echo 如果遇到连接时间过长问题，开个新终端执行 ping 192.168.255.1
	ssh -i "$(SSH_KEY)" -t root@192.168.255.1 || true
.PHONY: ssh

QEMU_VIRGL := y
QEMU_DEBUG := 0
KERNEL_DEFAULT_CMDLINE := console=tty1 console=ttyS0,115200 androidboot.enable_console=1 \
	SRC=. DEBUG=$(QEMU_DEBUG) VIRT_WIFI=1 video=1280x720
ifeq ($(NEW_DATA_MOUNT),y)
KERNEL_DEFAULT_CMDLINE += DATA=nodata data_part=/dev/vdb
else
KERNEL_DEFAULT_CMDLINE += DATA=/dev/vdb
endif
EXTRA_KERNEL_CMDLINE := 
QEMU_KERNEL_CMDLINE = $(KERNEL_DEFAULT_CMDLINE) $(EXTRA_KERNEL_CMDLINE)

ifeq ($(QEMU_VIRGL),n)
	QEMU_KERNEL_CMDLINE += nomodeset HWACCEL=0
endif
ifeq ($(QEMU_DEBUG),0)
	QEMU_KERNEL_CMDLINE += quiet
endif
KVM := y
QEMU_KVM :=
ifeq ($(KVM),y)
	QEMU_KVM := -enable-kvm
endif
QEMU_MEM := 2000
QEMU_KERNEL_FILE := $(wildcard $(KERNEL_DIR)/vmlinuz-* )
QEMU_INITRD_FILE := $(INITRD_FILE)
QEMU_SYSTEM_FILE := $(SYSTEM_FILE)
QEMU_DATA_FILE := $(BUILD_DIR)/data.qcow2
$(QEMU_DATA_FILE): $(DATA_FILE)
	qemu-img convert -f raw -O qcow2 "$<" "$@"
qemu: $(QEMU_INITRD_FILE) $(QEMU_SYSTEM_FILE) $(QEMU_DATA_FILE)
	GDK_BACKEND=x11 qemu-system-x86_64 -cpu Broadwell -M q35 -serial stdio \
	-kernel $(QEMU_KERNEL_FILE) -initrd "$(QEMU_INITRD_FILE)" -append "$(QEMU_KERNEL_CMDLINE)" \
	-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
	-device virtio-vga-gl -display gtk,gl=on,zoom-to-fit=off \
	-nic user,model=virtio-net-pci,mac=52:54:00:12:34:56,hostfwd=tcp::5555-:5555,hostfwd=tcp::5522-:22 \
	-m "$(QEMU_MEM)" -smp 4 $(QEMU_KVM) -device virtio-mouse-pci \
	-audiodev sdl,id=audio0 -device virtio-sound-pci,audiodev=audio0 \
	-drive file="$(QEMU_SYSTEM_FILE)",format=raw,if=virtio,id=system \
	-drive file="$(QEMU_DATA_FILE)",format=qcow2,if=virtio,id=data
qemu-iso:
	GDK_BACKEND=x11 qemu-system-x86_64 -cpu Broadwell -M q35 -serial stdio \
	-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
	-device virtio-vga-gl -display gtk,gl=on,zoom-to-fit=off \
	-nic user,model=virtio-net-pci,mac=52:54:00:12:34:56,hostfwd=tcp::5555-:5555,hostfwd=tcp::5522-:22 \
	-m "$(QEMU_MEM)" -smp 4 $(QEMU_KVM) -device virtio-mouse-pci \
	-audiodev sdl,id=audio0 -device virtio-sound-pci,audiodev=audio0 \
	-cdrom "$(ISO_FILE)" -hda "$(QEMU_DATA_FILE)"
mount_qemu_data: $(QEMU_DATA_FILE) umount_qemu_data
	sudo guestmount -a "$<" -m /dev/sda "$(DATA_DIR)"
umount_qemu_data:
	sudo guestunmount "$(DATA_DIR)" || echo "未挂载data.img"
clean_qemu:
	$(RM) $(QEMU_DATA_FILE)
.PHONY: qemu mount_qemu_data umount_qemu_data clean_qemu

dnx.7z: all
	7z a DNX_Fastboot.7z $(IMAGES_DIR)/*.img $(IMAGES_DIR)/*.simg $(PWD)/*.bat
.PHONY: dnx.7z

# 文件夹创建目标自动生成
# 注意 $(.VARIABLES) 会包含环境变量：构建环境里若存在 *_DIR 形式的变量
# （例如 SHELDON_DATA_DIR、XDG_RUNTIME_DIR），它们的值会被当成目标路径，
# 既会触发"目标在同一个规则中给出了多次"的警告，也会让 make 去创建项目
# 目录之外的系统目录。所以只保留项目根目录下的路径，并用 sort 去重。
DIR_VARS := $(filter %_DIR,$(.VARIABLES))
ALL_DIRS := $(sort $(filter $(O)/%,$(foreach v,$(DIR_VARS),$($(v)))) $(O))
$(ALL_DIRS):
	mkdir -p $@
